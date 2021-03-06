defmodule Bunck.Client do
  defstruct [:api_key, :client_private_key, :client_public_key, :server_public_key, :installation_token, :session_token, :headers]
  @moduledoc """
  Interacts with the Bunq API.
  """

  @doc """
  Performs the given request.

  Returns `{:ok, %Bunck.Response{}}`

  When there is an error, drops out with `{:error, reason}`

  ## Examples
  ```elixir
    iex> Bunck.Client.Request(%Bunck.User.List{}, client)
    {:ok, %Bunck.Response{...}}
  ```

  """
  def request(payload, client) do
    Bunck.Request.request(payload, client)
    |> headers(client)
    |> authenticate(client)
    |> sign(client)
    |> do_request(client)
  end

  @doc """
  Requests a session from the Bunq API and adds this to the Client struct, yielding it to the given function.

  This is the normal way to make a request.

  Returns the result of `fun.(client)`

  ## Examples
  ```elixir
    iex> Bunck.Client.with_session(fn(client) -> %Bunck.User.List{} |> Bunck.Client.request(client) end)
    {:ok, %Bunck.Response{...}}
  ```

  """
  def with_session(fun) do
    Bunck.DeviceServerWrapper.get_session_client() |> fun.()
  end

  @doc """
  Requests a session from the Bunq API with the provided API key and adds this to the Client struct, yielding it to the given function.

  Returns the result of `fun.(client)`

  ## Examples
  ```elixir
    iex> Bunck.Client.with_session(api_key, fn(client) -> %Bunck.User.List{} |> Bunck.Client.request(client) end)
    {:ok, %Bunck.Response{...}}
  ```

  """
  def with_session(api_key, fun) do
    Bunck.DeviceServerWrapper.get_session_client(api_key) |> fun.()
  end

  defp headers(request, client) do
    %Bunck.Request{request | headers: (request.headers || []) ++ (client.headers || []) ++ default_headers()}
  end

  defp default_headers do
    [
      "User-Agent": "Bunck Elixir Client/0.1 (+https://hex.pm/packages/bunck)",
      "Cache-Control": "no-cache",
      "X-Bunq-Language": "en_US",
      "X-Bunq-Region": "en_US",
      "X-Bunq-Client-Request-Id": UUID.uuid4(),
      "X-Bunq-Geolocation": "0 0 0 0 000",
    ]
  end

  defp authenticate(request = %Bunck.Request{payload: %Bunck.Installation.Post{}}, _client), do: request
  defp authenticate(request = %Bunck.Request{payload: %Bunck.SessionServer.Post{}}, client) do
    %{request | headers: ["X-Bunq-Client-Authentication": client.installation_token] ++ request.headers}
  end
  defp authenticate(request = %Bunck.Request{payload: %Bunck.DeviceServer.Post{}}, client) do
    %{request | headers: ["X-Bunq-Client-Authentication": client.installation_token] ++ request.headers}
  end
  defp authenticate(request, client) do
    %{request | headers: ["X-Bunq-Client-Authentication": client.session_token] ++ request.headers}
  end

  defp sign(request, client) do
    %{request | headers: ["X-Bunq-Client-Signature": signature(request, client)] ++ request.headers}
  end

  defp signature(_ = %Bunck.Request{payload: %Bunck.Installation.Post{}}, _client), do: ""
  defp signature(request, client) do
    headers_string =
      request.headers
      |> Enum.filter(fn header ->
        header_name = elem(header, 0)
        :"Cache-Control" == header_name || :"User-Agent" == header_name || header_name |> to_string() |> String.starts_with?("X-Bunq-")
      end)
      |> header_signature_string()

    "#{request.method |> String.upcase} #{request.path}\n#{headers_string}\n\n#{request.payload |> Poison.encode!}"
    |> :public_key.sign(:sha256, client.client_private_key)
    |> :base64.encode()
  end

  defp header_signature_string(headers) do
    headers
    |> Enum.sort_by(fn header -> elem(header, 0) end)
    |> Enum.map(fn header -> "#{elem(header, 0)}: #{elem(header, 1)}" end)
    |> Enum.join("\n")
  end

  defp format_request_for_hackney(request) do
    %{request | method: request.method |> String.downcase,
      url: "https://sandbox.public.api.bunq.com#{request.path}",
      payload: request.payload |> Poison.encode!(),
      options: request.options || [],
    }
    |> Map.take([:method, :url, :headers, :payload, :options])
  end

  defp do_request(request, client) do
    with {:ok, status, headers, body} <- do_hackney_request(request),
    {:ok, status, headers, body} <- validate_response({status, headers, body}, client),
    {:ok, status, headers, body} <- process_response_json({status, headers, body}) do
      {:ok, %Bunck.Response{status: status, headers: headers, body: body, client: client}}
    end
  end

  defp do_hackney_request(request) do
    r = request |> format_request_for_hackney()

    with {:ok, status, headers, body_stream} <- :hackney.request(r.method, r.url, r.headers, r.payload, r.options),
         {:ok, body} <- :hackney.body(body_stream),
    do: {:ok, status, headers, body}
  end

  defp validate_response({status, headers, body}, %{server_public_key: nil}), do: {:ok, status, headers, body}
  defp validate_response({status, headers, body}, client) do
    headers_string =
      headers
      |> Enum.filter(fn header ->
        name = elem(header, 0) |> to_string()
        name != "X-Bunq-Server-Signature" && name |> String.starts_with?("X-Bunq-")
      end)
      |> header_signature_string()

    signature_header =
      headers |> Enum.find(fn(header) -> elem(header, 0) == "X-Bunq-Server-Signature" end)

    if signature_header do
      signature =
        signature_header
        |> elem(1)
        |> :base64.decode()

      verified = "#{status}\n#{headers_string}\n\n#{body}"
                 |> :public_key.verify(:sha256, signature, server_public_key(client))

      if verified do
        {:ok, status, headers, body}
      else
        {:error, "Could not verify response signature. Check that you have the correct server public key."}
      end
    else
      {:ok, status, headers, body}
    end
  end

  defp process_response_json({status, headers, body}) do
    with {:ok, decoded_body} <- Poison.decode(body), do: {:ok, status, headers, decoded_body}
  end

  defp server_public_key(client) do
    client.server_public_key
    |> :public_key.pem_decode()
    |> List.first()
    |> :public_key.pem_entry_decode()
  end
end

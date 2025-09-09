defmodule ChatServer.CertificateManager do
  @moduledoc """
  Manages SSL certificates for the ChatServer, automatically generating
  self-signed certificates when needed and providing certificate fingerprints
  for client verification.

  This module handles the creation and management of SSL certificates required
  for secure client-server communication. It generates self-signed certificates
  using OpenSSL and provides fingerprint information for clients to verify
  server authenticity.

  ## Certificate Files
  The module manages three files:
  - `cert.pem` - The SSL certificate file
  - `key.pem` - The private key file
  - `server_fingerprint.txt` - Certificate fingerprint information

  ## Certificate Generation
  Certificates are automatically generated if they don't exist, using:
  - RSA 2048-bit key
  - Self-signed X.509 certificate
  - 365-day validity period
  - Common Name based on the provided hostname

  ## Hostname Resolution
  The Common Name (CN) in the certificate is determined by:
  - `"0.0.0.0"` → Uses `SSL_HOSTNAME` env var or defaults to `"localhost"`
  - `"127.0.0.1"` → Uses `"localhost"`
  - Other hostnames → Uses the provided hostname as-is

  ## Security Features
  - Generates SHA256 fingerprint for certificate verification
  - Displays formatted fingerprint on server startup
  - Saves fingerprint to file for easy client distribution
  - Provides export command for client environment setup

  ## Requirements
  - OpenSSL must be installed and available in PATH
  - Write permissions in the application directory

  ## Usage
    # Ensure certificates exist for localhost
    {cert_file, key_file} = CertificateManager.ensure_certificates()

    # Generate certificates for specific hostname
    {cert_file, key_file} = CertificateManager.ensure_certificates("myserver.com")

  The returned tuple contains the paths to the certificate and key files
  ready for use with SSL/TLS connections.
  """
  require Logger

  @cert_file "cert.pem"
  @key_file "key.pem"
  @fingerprint_file "server_fingerprint.txt"

  def ensure_certificates(host \\ "localhost") do
    if not files_exist?() do
      case System.find_executable("openssl") do
        nil ->
          raise "OpenSSL not found. Please install OpenSSL to generate certificates."

        _path ->
          cn = determine_common_name(host)
          generate_certificate(cn)
      end
    end

    show_certificate_info()
    {@cert_file, @key_file}
  end

  defp files_exist? do
    File.exists?(@cert_file) and File.exists?(@key_file)
  end

  defp determine_common_name(host) do
    case host do
      "0.0.0.0" -> System.get_env("SSL_HOSTNAME", "localhost")
      "127.0.0.1" -> "localhost"
      hostname when is_binary(hostname) -> hostname
      hostname -> to_string(hostname)
    end
  end

  defp generate_certificate(cn) do
    Logger.info("Generating SSL certificate for #{cn}...")

    case System.cmd("openssl", [
           "req",
           "-x509",
           "-newkey",
           "rsa:2048",
           "-nodes",
           "-keyout",
           @key_file,
           "-out",
           @cert_file,
           "-days",
           "365",
           "-subj",
           "/CN=#{cn}/O=ChatServer/C=US"
         ]) do
      {_, 0} ->
        Logger.info("Generated self-signed certificate for #{cn}")

      {output, code} ->
        raise "Failed to generate certificate (exit code #{code}): #{output}"
    end
  end

  defp show_certificate_info do
    fingerprint = get_certificate_fingerprint()
    formatted_fingerprint = format_fingerprint(fingerprint)

    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("SERVER CERTIFICATE FINGERPRINT:")
    IO.puts("#{formatted_fingerprint}")
    IO.puts("")
    IO.puts("For secure client connections:")
    IO.puts("export CHAT_SERVER_FINGERPRINT=#{fingerprint}")
    IO.puts("")
    IO.puts("Clients without fingerprint will show security warning")
    IO.puts(String.duplicate("=", 70) <> "\n")

    save_fingerprint_info(fingerprint, formatted_fingerprint)
  end

  defp get_certificate_fingerprint do
    case File.read(@cert_file) do
      {:ok, cert_data} ->
        [{:Certificate, cert_der, :not_encrypted}] = :public_key.pem_decode(cert_data)
        :crypto.hash(:sha256, cert_der) |> Base.encode16(case: :lower)

      {:error, reason} ->
        Logger.error("Failed to read certificate: #{inspect(reason)}")
        nil
    end
  end

  defp format_fingerprint(fingerprint) when is_binary(fingerprint) do
    fingerprint
    |> String.graphemes()
    |> Enum.chunk_every(2)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(":")
  end

  defp format_fingerprint(_), do: "unknown"

  defp save_fingerprint_info(fingerprint, formatted_fingerprint) do
    content = """
    # Server Certificate Information
    # Generated: #{DateTime.utc_now()}

    # Fingerprint (for client verification):
    #{fingerprint}

    # Formatted:
    #{formatted_fingerprint}

    # Usage:
    export CHAT_SERVER_FINGERPRINT=#{fingerprint}
    """

    File.write(@fingerprint_file, content)
    Logger.info("Certificate fingerprint saved to #{@fingerprint_file}")
  end
end

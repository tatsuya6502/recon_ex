defmodule ReconEx.Mixfile do
  use Mix.Project

  @version "0.9.1"

  def project do
    [app: :recon_ex,
     version: @version,
     elixir: "~> 1.1",
     description: "Elixir wrapper for Recon, diagnostic tools for production use",
     package: [
       maintainers: ["Tatsuya Kawano"],
       licenses: ["BSD 3-clause"],
       links: %{"GitHub" => "https://github.com/tatsuya6502/recon_ex"}
       ],
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    [applications: [:logger, :recon]]
  end

  defp deps do [
    {:recon, "~> 2.3"},
    {:ex_doc, "~> 0.18.1", only: :dev},
    {:earmark, "~> 1.2.3", only: :dev}
    # {:markdown, github: "devinus/markdown", only: :test}
  ]
  end

end

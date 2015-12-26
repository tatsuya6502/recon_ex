defmodule ReconEx.Mixfile do
  use Mix.Project

  @version "0.1.0"

  def project do
    [app: :recon_ex,
     version: @version,
     elixir: "~> 1.1",
     description: description,
     package: [
       maintaners: ["Tatsuya Kawano"],
       licenses: ["BSD 3-clause"],
       links: %{"GitHub" => "https://github.com/tatsuya6502/recon_ex"}
       ],
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  def application do
    []
    # [applications: [:logger]]
  end

  defp deps do [
    # ReconTrace reqires recon 2.3.0 or newer, which is not released yet.
    # Get it from GitHub.
    # {:recon, "~> 2.3.0"},
    {:recon, github: "ferd/recon"},
    {:ex_doc, "~> 0.10.0", only: :dev},
    {:earmark, "~> 0.1", only: :dev}
    # {:markdown, github: "devinus/markdown", only: :test}
  ]
  end

  defp description do
    """
    Elixir wrapper for Recon, tools to diagnose Erlang VM safely
    in production

    - Recon
      * gathers information about processes and the general state of
        the VM, ports, and OTP behaviours running in the node.
    - ReconAlloc
      * provides functions to deal with Erlang's memory allocators.
    - ReconLib
      * provides useful functionality used by Recon when dealing
        with data from the node.
    - ReconTrace
      * production-safe tracing facilities.
    """
  end

end

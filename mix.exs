defmodule AwsSDK.MixProject do
  use Mix.Project

  @mix_env Mix.env()
  @version "0.1.0"

  def project do
    [
      app: :aws_sdk,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix],
        plt_ignore_apps: [],
        plt_local_path: "dialyzer",
        plt_core_path: "dialyzer",
        list_unused_filters: true,
        ignore_warnings: ".dialyzer-ignore.exs",
        flags: [:unmatched_returns, :no_improper_lists]
      ]
    ]
  end

  def cli do
    [
      doctor: :test,
      coverage: :test,
      dialyzer: :test,
      coveralls: :test,
      "coveralls.lcov": :test,
      "coveralls.json": :test,
      "coveralls.html": :test,
      "coveralls.detail": :test,
      "coveralls.post": :test
    ]
  end

  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {AwsSDK.Application, []}
    ]
  end

  defp aliases do
    [
      compile: compile_alias()
    ]
  end

  defp compile_alias do
    if @mix_env === :test do
      "compile --warnings-as-errors"
    else
      "compile"
    end
  end

  defp docs do
    [
      main: "AwsSDK",
      extras: ["README.md"],
      groups_for_modules: [
        Core: [
          AwsSDK,
          AwsSDK.Error
        ],
        S3: [
          AwsSDK.S3
        ],
        EventBridge: [
          AwsSDK.EventBridge
        ],
        Logs: [
          AwsSDK.Logs
        ],
        SSM: [
          AwsSDK.SSM
        ],
        IAM: [
          AwsSDK.IAM
        ],
        "Identity Center": [
          AwsSDK.IdentityCenter
        ]
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false},
      {:credo, "~> 1.4", only: [:dev, :test], runtime: false},
      {:blitz_credo_checks, "~> 0.1.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.13", only: :test, runtime: false},
      # ---
      {:sandbox_registry, ">= 0.0.0", optional: true},
      # ---
      {:sweet_xml, "~> 0.7.5"},
      # Req 0.7 changed how the verb is inferred (a set body promotes GET to
      # POST) and how the Finch pool is named, so the range is pinned to what
      # `AwsSDK.HTTP` is written and tested against. `~> 0.5` resolved anything
      # below 1.0 and silently reintroduced both breaks.
      {:finch, "~> 0.21"},
      {:req, "~> 0.7"},
      {:cowboy, "~> 2.10", only: :test},
      {:error_message, "~> 0.3.3"},
      {:recase, "~> 0.9.1"},
      {:ex_utils, git: "https://github.com/cylkdev/ex_utils.git", branch: "main"}
    ]
  end
end

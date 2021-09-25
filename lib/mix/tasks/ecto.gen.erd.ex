defmodule Mix.Tasks.Ecto.Gen.Erd do
  @moduledoc """
  A mix task to generate an ERD (Entity Relationship Diagram) in various formats.

  Supported formats:
  * [DOT](#module-dot)
  * [PlantUML](#module-plantuml)
  * [DBML](#module-dbml)
  * [QuickDBD](#module-quickdbd)

  Configuration examples and output for a couple of open-source projects can be found in EXAMPLES group of PAGES section.

  ## DOT

  [DOT](https://en.wikipedia.org/wiki/DOT_(graph_description_language)) format is able to represent all available types of entities:
  * schemas
  * embedded schemas
  * schemaless tables (automatically derived from many-to-many relations)

  Clusters are supported and can be set in `:map_node` option using `Ecto.ERD.Node.set_cluster/2`.

  You should have installed [graphviz](https://graphviz.org/) in order to convert `*.dot` file to image.

  ```
  $ mix ecto.gen.erd # generates ecto_erd.dot
  $ mix ecto.gen.erd --output-path=ecto_erd.dot
  $ mix ecto.gen.erd && dot -Tpng ecto_erd.dot -o erd.png && xdg-open erd.png
  ```

  ## PlantUML

  [PlantUML](https://plantuml.com) is equal to DOT in number of supported features.

  You should have installed [plantuml](https://plantuml.com/download) in order to convert `*.puml` file to image.

  ```
  $ mix ecto.gen.erd --output-path=erd.puml
  $ mix ecto.gen.erd --output-path=erd.puml && plantuml erd.puml && xdg-open erd.png
  ```
  *Tip: if output image is cropped, you may need to adjust image size with `PLANTUML_LIMIT_SIZE` environment variable.*

  ## DBML

  [DBML](https://www.dbml.org/) format is more limited in number of displayed entity types comparing to DOT and PlantUML, as it is focused on tables only.
  Multiple schemas that use the same table are merged into one table. Embedded schemas, obviously,
  cannot be displayed at all.
  `TableGroup`s are supported and can be set in `:map_node` option using `Ecto.ERD.Node.set_cluster/2`.

  This format is very handy if you use [dbdiagram.io](https://dbdiagram.io) or [dbdocs.io](https://dbdocs.io).

  ```
  $ mix ecto.gen.erd --output-path=ecto_erd.dbml
  ```

  ## QuickDBD

  A format that is used by [QuickDBD](https://www.quickdatabasediagrams.com) - a competitor of [dbdiagram.io](https://dbdiagram.io).
  Similarly to DBML, it is also focused on tables and cannot display embeded schemas. However, this format doesn't support clusters.

  It doesn't have a reserved file extension, but we use `*.qdbd`.

  ```
  $ mix ecto.gen.erd --output-path=ecto_erd.qdbd
  ```

  ## Command line options

  * `--output-path` - the path to the output file, defaults to `ecto_erd.dot`. Supported file extensions: `dot`, `puml`, `dbml`, `qdbd`.
  * `--config-path` - the path to the config file, defaults to `.ecto_erd.exs`.

  ## Configuration file

  When running a `mix ecto.gen.erd` task, it tries to read a configuration file from the `.ecto_erd.exs` file in a current
  working directory. Configuration file must return a keyword list.

  ### Options

  * `:fontname` - font name, defaults to `Roboto Mono`. Must be monospaced font if output format is `dot` and more than 1 column is displayed.
  The option is only supported for `dot` and `puml` files.
  * `:columns` - list of columns which will be displayed for each node (schema/source). Set to `[]` to hide fields completelly.
  Available columns: `:name` and `:type`. Defaults to `[:name, :type]`.  The option is only supported for `dot` and `puml` files.
  * `:map_node` - function which allows to remove the node from the diagram or to move the node to the cluster. Defaults to `Function.identity/1`,
  which means that all nodes should be displayed and all of them are outside any cluster.
  Use `Ecto.ERD.Node.set_cluster/2` in this function to set a cluster (not supported by [QuickDBD](#module-quickdbd)).
  In order to remove the node, the function must return `nil`.
  * `:otp_app` - an application which will be scanned alongside with dependent applications in order to get a list of Ecto schemas.
  Defaults to `Mix.Project.config()[:app]`. You need to configure this option only if you run a task from the umbrella root.

  Default values can be represented as follows:

      # .ecto_erd.exs
      [
        fontname: "Roboto Mono", # used only by dot and puml
        columns: [:name, :type], # used only by dot and puml
        map_node: &Function.identity/1,
        otp_app: Mix.Project.config()[:app]
      ]

  """
  @shortdoc "Generate an ERD"
  use Mix.Task
  @requirements ["app.config"]

  @impl true
  def run(args) do
    {cli_opts, _} =
      OptionParser.parse!(args, strict: [output_path: :string, config_path: :string])

    config_path = Keyword.get(cli_opts, :config_path, ".ecto_erd.exs")

    file_opts =
      if File.exists?(config_path) do
        {file_opts, _} = Code.eval_file(config_path)
        file_opts
      else
        []
      end

    otp_app =
      cond do
        Keyword.has_key?(file_opts, :otp_app) -> file_opts[:otp_app]
        not is_nil(Mix.Project.config()[:app]) -> Mix.Project.config()[:app]
        true -> raise "Unable to detect `:otp_app`, please specify it explicitly"
      end

    output_path = cli_opts[:output_path] || file_opts[:output_path] || "ecto_erd.dot"
    map_node_callback = file_opts[:map_node] || (&Function.identity/1)

    schema_modules = Ecto.ERD.SchemaModules.scan(otp_app)

    output =
      case Path.extname(output_path) do
        ".dot" ->
          fontname = file_opts[:fontname] || "Roboto Mono"
          columns = file_opts[:columns] || [:name, :type]

          schema_modules
          |> Ecto.ERD.Graph.new([:associations, :embeds])
          |> Ecto.ERD.Graph.map_nodes(map_node_callback)
          |> Ecto.ERD.Graph.sort()
          |> Ecto.ERD.Dot.render(fontname: fontname, columns: columns)


        ".puml" ->
          fontname = file_opts[:fontname] || "Roboto Mono"
          columns = file_opts[:columns] || [:name, :type]

          schema_modules
          |> Ecto.ERD.Graph.new([:associations, :embeds])
          |> Ecto.ERD.Graph.map_nodes(map_node_callback)
          |> Ecto.ERD.Graph.sort()
          |> Ecto.ERD.PlantUML.render(fontname: fontname, columns: columns)

        ".dbml" ->
          schema_modules
          |> Ecto.ERD.Graph.new([:associations])
          |> Ecto.ERD.Graph.map_nodes(map_node_callback)
          |> Ecto.ERD.Graph.make_schemaless()
          |> Ecto.ERD.Graph.sort()
          |> Ecto.ERD.DBML.render()

        ".qdbd" ->
          schema_modules
          |> Ecto.ERD.Graph.new([:associations])
          |> Ecto.ERD.Graph.map_nodes(map_node_callback)
          |> Ecto.ERD.Graph.make_schemaless()
          |> Ecto.ERD.Graph.sort()
          |> Ecto.ERD.QuickDBD.render()
      end

    File.write!(output_path, output)
  end
end

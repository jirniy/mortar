require "clamp"
require_relative "yaml_file"

Clamp.allow_options_after_parameters = true

module Mortar
  class Command < Clamp::Command
    banner "mortar - Kubernetes manifest shooter"

    option ['-v', '--version'], :flag, "print mortar version" do
      puts "mortar #{Mortar::VERSION}"
      exit 0
    end
    option ["-d", "--debug"], :flag, "debug"

    parameter "NAME", "deployment name"
    parameter "SRC", "source folder"

    LABEL = 'mortar.kontena.io/shot'
    CHECKSUM_ANNOTATION = 'mortar.kontena.io/shot-checksum'

    def execute
      signal_usage_error("#{src} is not a directory") unless File.exist?(src)
      stat = File.stat(src)
      signal_usage_error("#{src} is not a directory") unless stat.directory?

      resources = from_files(src)

      #K8s::Logging.verbose!
      K8s::Stack.new(
        name, resources,
        debug: debug?,
        label: LABEL, 
        checksum_annotation: CHECKSUM_ANNOTATION
      ).apply(client)
      puts "pushed #{name} successfully!"
    end

    # @param filename [String] file path
    # @return [Array<K8s::Resource>]
    def from_files(path)
      Dir.glob("#{path}/*.{yml,yaml}").sort.map { |file| self.from_file(file) }.flatten
    end

    # @param filename [String] file path
    # @return [K8s::Resource]
    def from_file(filename)
      K8s::Resource.new(YamlFile.new(filename).load)
    end

    # @return [K8s::Client]
    def client
      return @client if @client

      if ENV['KUBECONFIG']
        @client = K8s::Client.config(K8s::Config.load_file(ENV['KUBECONFIG']))
      else
        @client = K8s::Client.in_cluster_config
      end
    end
  end
end
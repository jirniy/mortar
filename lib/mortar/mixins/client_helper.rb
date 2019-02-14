# frozen_string_literal: true

module Mortar
  module ClientHelper
    # @return [K8s::Client]
    def client
      @client ||= create_client
    end

    def create_client
      K8s::Client.autoconfig
    end
  end
end

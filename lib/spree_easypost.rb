require 'spree_core'

module Spree
  module EasyPost
    
    class << self
      attr_accessor :configuration
    end
    
    def self.configure
      self.configuration ||= Configuration.new
      yield(configuration) if block_given?
    end
    
    class Configuration
      attr_accessor :filter_services_list
      
      def initialize
        @filter_services_list = []
      end
      
    end
    
  end
end

require 'easypost'
require 'spree_easypost/engine'

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/segment'
require 'new_relic/agent/transaction/datastore_segment'
require 'new_relic/agent/transaction/external_request_segment'
require 'new_relic/agent/transaction/message_broker_segment'

module NewRelic
  module Agent
    class Transaction
      module Tracing
        module ClassMethods
          def start_segment name, unscoped_metrics=nil
            segment = Segment.new name, unscoped_metrics
            start_and_add_segment segment
          end

          UNKNOWN_PRODUCT = "Unknown".freeze
          UNKNOWN_OPERATION = "other".freeze

          def start_datastore_segment product=nil, operation=nil, collection=nil, host=nil, port_path_or_id=nil, database_name=nil
            product ||= UNKNOWN_PRODUCT
            operation ||= UNKNOWN_OPERATION
            segment = DatastoreSegment.new product, operation, collection, host, port_path_or_id, database_name
            start_and_add_segment segment
          end

          def start_external_request_segment library, uri, procedure
            segment = ExternalRequestSegment.new library, uri, procedure
            start_and_add_segment segment
          end

          # @api private
          #
          def start_message_broker_segment(action: nil,
                                           library: nil,
                                           destination_type: nil,
                                           destination_name: nil,
                                           headers: nil,
                                           parameters: nil,
                                           start_time: nil)

            # ruby 2.0.0 does not support required kwargs
            raise ArgumentError, 'missing required argument: action' if action.nil?
            raise ArgumentError, 'missing required argument: library' if library.nil?
            raise ArgumentError, 'missing required argument: destination_type' if destination_type.nil?
            raise ArgumentError, 'missing required argument: destination_name' if destination_name.nil?

            segment = MessageBrokerSegment.new(
              action: action,
              library: library,
              destination_type: destination_type,
              destination_name: destination_name,
              headers: headers,
              parameters: parameters,
              start_time: start_time
            )
            start_and_add_segment segment
          end

          private

          def start_and_add_segment segment
            segment.start
            add_segment segment
            segment
          end

          def add_segment segment
            state = NewRelic::Agent::TransactionState.tl_get
            if (txn = state.current_transaction) && state.is_execution_traced?
              txn.add_segment segment
            else
              segment.record_metrics = false
            end
          end
        end

        def self.included base
          base.extend ClassMethods
        end

        attr_reader :current_segment

        def add_segment segment
          segment.transaction = self
          segment.parent = current_segment
          @current_segment = segment
          if @segments.length < segment_limit
            @segments << segment
          else
            segment.record_on_finish = true
            ::NewRelic::Agent.logger.debug("Segment limit of #{segment_limit} reached, ceasing collection.")
          end
        end

        def segment_complete segment
          @current_segment = segment.parent
        end

        def segment_limit
          Agent.config[:'transaction_tracer.limit_segments']
        end
      end
    end
  end
end

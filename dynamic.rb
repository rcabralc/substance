# frozen_string_literal: true

require_relative './scheme_params_from_srgb'

module Substance
	Dynamic = Scheme.new(SchemeParamsFromSrgb.from_environment)

	Dynamic.print if __FILE__ == $0
end

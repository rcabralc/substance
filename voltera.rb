# frozen_string_literal: true

require_relative './scheme_params_from_srgb'

module Substance
	Voltera = Scheme.new(SchemeParamsFromSrgb.from_seed('#308434,31542,0.025,,0,5'))

	Voltera.print if __FILE__ == $0
end

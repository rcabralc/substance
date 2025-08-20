# frozen_string_literal: true

require_relative './scheme_params_from_srgb'

module Substance
	Bubbaloo = Scheme.new(SchemeParamsFromSrgb.from_seed('#c3437e,15432,,,1'))

	Bubbaloo.print if __FILE__ == $0
end

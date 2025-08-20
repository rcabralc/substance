# frozen_string_literal: true

require_relative './scheme_params_from_srgb'

module Substance
	Bia = Scheme.new(SchemeParamsFromSrgb.from_seed('#9648cd,14352,0.02,0.085,1,2'))
	Bia.print if __FILE__ == $0
end

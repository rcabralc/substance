# frozen_string_literal: true

require_relative './substance'

module Substance
	Redefined = Scheme.new(
		tier1: OKLrch[0, 0.135, 10],
		tier2: OKLrch[0, 0.135, 290],
		tier3: OKLrch[0, 0.135, 80],
		tier4: OKLrch[0, 0.135, 260],
		tier5: OKLrch[0, 0.135, 180],
		tier6: OKLrch[0, 0.135, 330],
		neutral: OKLrch[0, 0.015, 60],
		neutral_variant: OKLrch[0, 0.02, 60],
		link: :tier1,
		link_visited: :tier2,
		warning: :tier3,
		positive: :tier5,
		term1: :tier1,
		term4: :tier2,
		term5: :tier6,
		error: :tier6
	)

	Redefined.print if __FILE__ == $0
end

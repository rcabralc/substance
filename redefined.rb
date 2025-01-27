# frozen_string_literal: true

require_relative './substance'

module Substance
	Redefined = Scheme.new(
		tier1: OKLrch[0, 0, 25],
		tier2: OKLrch[0, 0, 285],
		tier3: OKLrch[0, 0, 70],
		tier4: OKLrch[0, 0, 245],
		tier5: OKLrch[0, 0, 130],
		tier6: OKLrch[0, 0, 340],
		neutral: OKLrch[0, 0.015, 68],
		neutral_variant: OKLrch[0, 0.033, 68],
		value: :tier6,
		error: :tier1,
		positive: :tier5,
		warning: :tier3,
		link: :tier1,
		link_visited: :tier6,
		active: :tier4,
		term4: :tier2,
		highlight: :tier5,
	)

	Redefined.print if __FILE__ == $0
end

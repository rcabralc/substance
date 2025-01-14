# frozen_string_literal: true

require_relative './substance'
require 'ostruct'

module Substance
	class HueRange
		def initialize(begin_, end_)
			if begin_ < end_
				raise 'interval too large' if end_ - begin_ > 360
				@begin = begin_ % 360
				@end = end_ % 360
				@shift = 0
			else
				@shift = 360 - (begin_ % 360)
				@begin = (begin_ + @shift) % 360
				@end = (end_ + @shift) % 360
			end

			@end = 360 if @end == 0
			@sub = @begin...@end
			@mid_delta = (@end - @begin) / 2.0
		end

		def include?(angle)
			@sub.include?((angle + @shift) % 360)
		end

		def deviation(angle)
			(((angle + @shift) % 360 - @begin) / @mid_delta - 1.0).abs
		end

		def inspect
			"#{(@begin - @shift) % 360}...#{(@end - @shift) % 360}"
		end
	end

	class NamedHueRange < HueRange
		attr_reader :name

		VALID_NAMES = %i[error positive warning active link link_visited]

		def initialize(name, begin_, end_)
			raise "name must be one of #{VALID_NAMES.map(&:to_s).join(',')}" unless VALID_NAMES.include?(name)

			@name = name
			super(begin_, end_)
		end

		def inspect
			"#<#{name} #{super}>"
		end
	end

	class SchemeParamsFromSrgb
		RANGES = [
			NamedHueRange.new(:error, 350, 30),
			NamedHueRange.new(:warning, 30, 120),
			NamedHueRange.new(:positive, 120, 190),
			NamedHueRange.new(:active, 190, 245),
			NamedHueRange.new(:link, 245, 290),
			NamedHueRange.new(:link_visited, 290, 350),
		].freeze

		def initialize(hex, quadrants)
			@hex = hex.strip.gsub(/^#/, '')
			@quadrants = quadrants.split('').map(&:to_i)
		end

		def to_hash
			params
		end

		def each(&)
			params.each(&)
		end

		private

		def params
			return @params if defined? @params

			tiers = compute_tiers(@quadrants)
			colors_map = match_ranges(RANGES, tiers)

			@params = {
				**tiers.map { |tier| [tier.name, OKLrch[0, 0, tier.hue]] }.to_h,
				neutral: OKLrch[0, 0.025, tier1_hue],
				neutral_variant: OKLrch[0, 0.06, tier1_hue],
				**colors_map,
			}.freeze
		end

		def compute_tiers(quadrants)
			raise "quadrants must specify four regions" if quadrants.size != 4
			raise "quadrants must contain and only contain 1, 2, 3 and 4." if ([1, 2, 3, 4] - quadrants).any?

			tier2_hue = (tier1_hue + 180) % 360
			tier3_hue, tier4_hue, tier5_hue, tier6_hue = quadrants.map do |region|
				case region
				when 1 then (tier1_hue + 60) % 360
				when 2 then (tier2_hue - 60) % 360
				when 3 then (tier2_hue + 60) % 360
				when 4 then (tier1_hue - 60) % 360
				end
			end

			[
				OpenStruct.new(hue: tier1_hue, name: :tier1),
				OpenStruct.new(hue: tier2_hue, name: :tier2),
				OpenStruct.new(hue: tier3_hue, name: :tier3),
				OpenStruct.new(hue: tier4_hue, name: :tier4),
				OpenStruct.new(hue: tier5_hue, name: :tier5),
				OpenStruct.new(hue: tier6_hue, name: :tier6)
			]
		end

		def match_ranges(ranges, tiers)
			# assumption: ranges don't overlap
			possible_combos = ranges.permutation.map { |p| p.zip(tiers) }
			possible_combos.min_by do |combo|
				combo.sum { |range, tier| range.deviation(tier.hue) }
			end.map { |range, tier| [range.name, tier.name] }.to_h
		end

		def tier1_hue
			return @tier1_hue if defined? @tier1_hue

			rgb = Vector[*@hex.chars.each_slice(2).map { |s| s.join.to_i(16) / 255.0 }]
			linear_rgb = rgb.map do |c|
				c.abs <= 0.04045 ?
					c / 12.92 :
					(c < 0 ? -1 : 1) * (((c.abs + 0.055) / 1.055) ** 2.4)
			end
			xyz = Matrix[
				[0.41239079926595934, 0.357584339383878,   0.1804807884018343 ],
				[0.21263900587151027, 0.715168678767756,   0.07219231536073371],
				[0.01933081871559182, 0.11919477979462598, 0.9505321522496607 ],
			] * linear_rgb
			lms = Matrix[
				[0.8190224379967030, 0.3619062600528904, -0.1288737815209879],
				[0.0329836539323885, 0.9292868615863434,  0.0361446663506424],
				[0.0481771893596242, 0.2642395317527308,  0.6335478284694309],
			] * xyz
			lmsg = lms.map { |c| c ** (1.0 / 3) }

			oklab = OKLab[*Matrix[
				[0.2104542683093140,  0.7936177747023054, -0.0040720430116193],
				[1.9779985324311684, -2.4285922420485799,  0.4505937096174110],
				[0.0259040424655478,  0.7827717124575296, -0.8086757549230774],
			] * lmsg]
			@tier1_hue = oklab.oklch.h
		end
	end

	params = SchemeParamsFromSrgb.new(
		ENV['SUBSTANCE_DYNAMIC_BASE_COLOR'] || '#ff0000',
		ENV['SUBSTANCE_DYNAMIC_QUADRANTS_ORDER'] || '1423'
	)
	Dynamic = Scheme.new(**params)

	Dynamic.define_singleton_method(:print) do |params|
		params.each do |name, param|
			puts "#{name}: #{param.respond_to?(:h) ? param.h : param}"
		end
		super()
	end

	Dynamic.print(params) if __FILE__ == $0
end

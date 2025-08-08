# frozen_string_literal: true

require_relative './substance'
require 'ostruct'

module Substance
	class NamedColor
		attr_reader :name

		def initialize(name, color)
			@name = name
			@color = color
		end

		def inspect
			"#<#{name} #{@color.inspect}>"
		end

		def ΔE(hue)
			OKLrch[@color.lr, @color.c, hue].ΔE(@color, mode: :ok)
		end
	end

	class Average
		def initialize(values)
			@values = values
		end

		def value
			@value ||= @values.sum(0.0) / size
		end

		alias :to_f :value

		def σ
			@σ ||= Math.sqrt(@values.sum(0.0) { |d| (d - value) ** 2 } / size)
		end

		def to_s
			value.to_s
		end

		private

		def size
			@values.size
		end
	end

	class SchemeParamsFromSrgb
		COLORS = [
			NamedColor.new(:active, OKLrch.from_hex('00ffff')),
			NamedColor.new(:error, OKLrch.from_hex('ff0000')),
			NamedColor.new(:link, OKLrch.from_hex('0000ff')),
			NamedColor.new(:link_visited, OKLrch.from_hex('ff00ff')),
			NamedColor.new(:positive, OKLrch.from_hex('00ff00')),
			NamedColor.new(:warning, OKLrch.from_hex('ff7f00')),
		]

		def initialize(**kw)
			@hex = kw.fetch(:hex)
			@points = kw.fetch(:points)
			@neutral_chroma = kw.fetch(:neutral_chroma)
			@neutral_variant_chroma = kw.fetch(:neutral_variant_chroma)
			@neutral_color_point = kw.fetch(:neutral_color_point)
			@neutral_variant_color_point = kw.fetch(:neutral_variant_color_point)
		end

		def to_hash
			params
		end

		def each(&)
			params.each(&)
		end

		def seed
			[
				@hex.downcase,
				@points.join,
				@neutral_chroma,
				@neutral_variant_chroma,
				@neutral_color_point,
				@neutral_variant_color_point,
			].join(',')
		end

		private

		def params
			return @params if defined? @params

			spaced_hues = compute_spaced_hues
			tiers = build_tiers(spaced_hues)
			colors_map = match_ranges(COLORS, tiers)
			neutral_hue = spaced_hues[@neutral_color_point]
			neutral_variant_hue = spaced_hues[@neutral_variant_color_point]

			@params = {
				**tiers.map { |tier| [tier.name, OKLrch[0, 0, tier.hue]] }.to_h,
				neutral: OKLrch[0, @neutral_chroma, neutral_hue],
				neutral_variant: OKLrch[0, @neutral_variant_chroma, neutral_variant_hue],
				**colors_map,
			}.freeze
		end

		def compute_spaced_hues
			hues = Array.new(5) { |i| (tier1_hue + (i + 1) * 60) % 360 }
      smoothly_space_hues(tier1_hue, *hues)
		end

		def build_tiers(spaced_hues)
      tiers = [tier1_hue, *@points.map { |p| spaced_hues[p] }]
      tiers.each_with_index.map do |hue, i|
				OpenStruct.new(hue:, name: :"tier#{i + 1}")
      end
		end

		def match_ranges(colors, tiers)
			possible_combos = colors.permutation.map { |p| p.zip(tiers) }
			possible_combos.min_by do |combo|
				combo.sum { |color, tier| color.ΔE(tier.hue) ** 2 }
			end.map { |color, tier| [color.name, tier.name] }.to_h
		end

		def tier1_hue
			@tier1_hue ||= OKLrch.from_hex(@hex).h
		end

		def smoothly_space_hues(tier1_hue, *initial_hues)
			lr = 0.53
      colors = [tier1_hue, *initial_hues].map do |h|
	      OKLrch[lr, 0.5, h].scale_max_srgb_chroma
      end

			delta_E = -> (a, b) { a.ΔE(b, mode: :ciede2000) }

			ε = 0.1
			loop do
				changed = false

				average = Average.new(adjacent_distances(colors, &delta_E))
				break if average.σ <= ε

				(1..5).each do |i|
					color = colors[i]
					prev_color = colors[i - 1]
					next_color = colors[(i + 1) % colors.size]
					distance = delta_E.call(color, prev_color)
					next unless distance > average.to_f

					changed = true
					colors[i] = find_color(color, prev_color.h, color.h) do |color|
						average.to_f <=> delta_E.call(color, prev_color)
					end
					average = Average.new(adjacent_distances(colors, &delta_E))
				end

				average = Average.new(adjacent_distances(colors, &delta_E))
				break if average.σ <= ε

				(1..5).reverse_each do |i|
					color = colors[i]
					prev_color = colors[i - 1]
					next_color = colors[(i + 1) % colors.size]
					distance = delta_E.call(color, next_color)
					next unless distance > average.to_f

					changed = true
					colors[i] = find_color(color, color.h, next_color.h) do |color|
						delta_E.call(color, next_color) <=> average.to_f
					end
					average = Average.new(adjacent_distances(colors, &delta_E))
				end

				break unless changed
			end

			colors.map(&:h)
		end

		def find_color(color, min_hue, max_hue, &)
			raise "hue range too large: #{min_hue} #{max_hue}" if (max_hue - min_hue) % 360 > 180.0

			result = yield color
			new_hue, min_hue, max_hue =
				if result > 0
					[(color.h + max_hue) / 2.0, color.h, max_hue]
				elsif result < 0
					[(color.h + min_hue) / 2.0, min_hue, color.h]
				else
					return color
				end

			new_hue += 180 if new_hue < min_hue
			new_hue %= 360

			new_color = color.call(nil, nil, new_hue).scale_max_srgb_chroma
			return new_color if (new_color.h - color.h).abs < 0.0001

			find_color(new_color, min_hue, max_hue, &)
		end

		def adjacent_distances(colors, &)
			[*colors, colors.first].each_cons(2).map { |a, b| yield a, b }
		end

		class << self
			def from_environment
				seed = ENV['SUBSTANCE_DYNAMIC_SEED'] || ''
				from_seed(seed)
			end

			def from_seed(seed)
				new(**parse_seed(seed))
			end

		private

			def parse_seed(seed)
				hex,
					points,
					neutral_chroma,
					neutral_variant_chroma,
					neutral_color_point,
					neutral_variant_color_point =
					seed.split(',').map { |s| s.empty?? nil : s }

				hex = (hex || 'ff0000').strip.gsub(/^#/, '')
				unless hex.downcase.match?(/[a-f0-9]{6}/)
					raise "seed color must specify valid hex RGB color: #{seed}"
				end

				points ||= '31524'
				points = points.split('').map(&:to_i)

				if points.size != 5
					raise "seed points must specify five values: #{seed}"
				end

				if ([1, 2, 3, 4, 5] - points).any?
					raise "seed points must contain and only contain 1, 2, 3, 4 and 5: #{seed}"
				end

				neutral_chroma ||= '0'
				neutral_chroma = neutral_chroma.to_f

				neutral_variant_chroma ||= '0.05'
				neutral_variant_chroma = neutral_variant_chroma.to_f

				neutral_color_point ||= '0'
				neutral_variant_color_point ||= neutral_color_point

				neutral_color_point = neutral_color_point.to_i
				neutral_variant_color_point = neutral_variant_color_point.to_i

				if neutral_color_point < 0 || neutral_color_point > 5
					raise "neutral_color_point must be between 0 and 5"
				end

				if neutral_variant_color_point < 0 || neutral_variant_color_point > 5
					raise "neutral_variant_color_point must be between 0 and 5"
				end

				{
					hex:,
					points:,
					neutral_chroma:,
					neutral_variant_chroma:,
					neutral_color_point:,
					neutral_variant_color_point:,
				}
			end
		end
	end

	module SchemeMixin
		def initialize(params)
			@params = params
			super(**@params)
		end

		def seed
			@params.seed
		end

		def print
			@params.each do |name, param|
				puts "#{name}: #{param.respond_to?(:h) ? param.h : param}"
			end
			puts "seed: #{@params.seed}"
			super()
		end
	end

	class Scheme
		prepend SchemeMixin
	end
end

require 'matrix'

module Substance
	# Conversion matrices and formulas from
	# https://drafts.csswg.org/css-color-4/#color-conversion-code

	LMStoXYZ = Matrix[
		[ 1.2268798733741557,  -0.5578149965554813,  0.28139105017721583],
		[-0.04057576262431372,  1.1122868293970594, -0.07171106666151701],
		[-0.07637294974672142, -0.4214933239627914,  1.5869240244272418 ]
	]

	OKLabtoLMS = Matrix[
		[0.99999999845051981432, 0.39633779217376785678,   0.21580375806075880339 ],
		[1.0000000088817607767, -0.1055613423236563494,   -0.063854174771705903402],
		[1.0000000546724109177, -0.089484182094965759684, -1.2914855378640917399  ]
	]

	XYZtoLinearSRGB = Matrix[
		[ 3.2409699419045226,  -1.537383177570094,   -0.4986107602930034 ],
		[-0.9692436362808796,   1.8759675015077202,   0.04155505740717559],
		[ 0.05563007969699366, -0.20397695888897652,  1.0569715142428786 ]
	]

	Channels = -> *channels, other: [] do
		Class.new do
			attr_reader(*channels, *other)

			define_singleton_method(:[]) do |*args|
				new(*args)
			end

			define_method(:initialize) do |*args|
				[*channels, *other].zip(args).each do |name, arg|
					instance_variable_set(:"@#{name}", arg)
				end
			end

			define_method(:[]) do |index|
    			to_a[index]
			end

			define_method(:to_a) do
				channels.map { |name| public_send(name) }
			end
		end
	end

	class OKLch < Channels[:l, :c, :h]
		def initialize(l, c, h)
			h = h % 360
			super
		end

		def call(l = nil, c = nil, h = nil)
			l ||= @l
			c ||= @c
			h ||= @h
			self.class.new(l, c, h)
		end

		def srgb
			@srgb ||= oklab.srgb
		end

	private

		def oklab
			OKLab.from_lch(@l, @c, @h)
		end
	end

	# This is a modified version of OKLch color space, designed to have its
	# L component (called Lr) more perceptually uniform (like L*a*b).
	# The color is defined using Lr instead of L, as proposed by Björn Ottosson
	# in
	# See https://bottosson.github.io/posts/colorpicker/#intermission---a-new-lightness-estimate-for-oklab.
	# These modifications assume a reference white with luminance of Y = 1.
	#
	# UPDATE: to more closely perceptually match HCT from Google, different k1
	# and k2 are proposed in
	# https://facelessuser.github.io/coloraide/playground/?notebook=https%3A%2F%2Fgist.githubusercontent.com%2Ffacelessuser%2F0235cb0fecc35c4e06a8195d5e18947b%2Fraw%2F3ca56c388735535de080f1974bfa810f4934adcd%2Fexploring-tonal-palettes.md
	class OKLrch < OKLch
		# Values proposed by Björn Ottosson to match L*a*b:
		# K1 = 0.206
		# K2 = 0.03

		# Values proposed by facelessuser (creator of ColorAide lib) to better match HCT:
		K1 = 0.173
		K2 = 0.004

		K3 = (1 + K1) / (1 + K2)

		def initialize(lr, c, h)
			l = lr * (lr + K1) / (lr + K2) / K3
			@lr = lr
			super(l, c, h)
		end

		def call(lr = nil, c = nil, h = nil)
			lr ||= @lr
			c ||= @c
			h ||= @h
			self.class.new(lr, c, h)
		end

		def l
			@lr
		end

		def dechromatize(factor)
			lr, c, h = adjust_chroma(maximize: true).to_a
			c *= [1, factor].min
			self.class.new(lr, c, h)
		end

		def adjust_chroma(maximize: false)
			if srgb.in_gamut?
				return self unless maximize

				# Increase chroma while conversion stays in SRGB gamut within a certain tolerance.
				hi = 0.5
				lo = @c
			else
				# Reduce chroma until conversion reaches SRGB gamut within a certain tolerance.
				# Adapted from https://github.com/LeaVerou/css.land/blob/master/lch/lch.js
				hi = @c
				lo = 0
			end

			ε = 0.0001
			c = (hi + lo) / 2
			while hi - lo > ε
				if OKLab.from_lch(@l, c, @h).srgb.in_gamut?
					lo = c
				else
					hi = c
				end
				c = (hi + lo) / 2
			end

			self.class.new(@lr, c, @h)
		end
	end

	class OKLab < Channels[:l, :a, :b]
		def srgb
			xyz.srgb
		end

		def self.from_lch(l, c, h)
			new(l, c * Math.cos(h * Math::PI / 180), c * Math.sin(h * Math::PI / 180))
		end

		def oklch
			hr = a.nonzero? ? Math.atan(b / a) : (b.negative? ? 3 * Math::PI / 2 : Math::PI)
			OKLch.new(@l, Math.sqrt(a * a + b * b), hr * 180 / Math::PI)
		end

		def oklab
			self
		end

	private

		def xyz
			lms = OKLabtoLMS * Vector[l, a, b]
			XYZ.new(*(LMStoXYZ * lms.map { |c| c ** 3 }))
		end
	end

	class XYZ < Channels[:x, :y, :z]
		def srgb
			linear_srgb.srgb
		end

	private

		def linear_srgb
			LinearSRGB.new(*(XYZtoLinearSRGB * Vector[x, y, z]), self)
		end
	end

	class LinearSRGB < Channels[:r, :g, :b, other: [:xyz]]
		def srgb
			sr, sg, sb = [r, g, b].map do |c|
				sign = c < 0 ? -1 : 1
				c = c.abs
				sign * (c > 0.0031308 ? 1.055 * (c**(1 / 2.4)) - 0.055 : 12.92 * c)
			end

			SRGB.new(sr, sg, sb, self)
		end

		def relative_luminance
			@xyz.y
		end
	end

	class SRGB < Channels[:r, :g, :b, other: [:linear]]
		def relative_luminance
			@linear.relative_luminance
		end

		def hex
			@hex ||= format("#%02x%02x%02x", *octets)
		end

		def octets
			clamped.map { |c| (c * 255).round }
		end

		def in_gamut?
			ε = 0.000005
			[@r, @g, @b].all? { |c| c >= -ε && c <= 1 + ε }
		end

	private

		def clamped
			to_a.map { |c| [[0, c].max, 1].min }
		end
	end

	class Swatch
		def initialize(name, color, fg, base_acronym, show_spec: true, lines_count: 2, line_length: 18)
			@name = name
			@color = color
			@fg = fg
			@base_acronym = base_acronym
			@tone = @color.l * 100
			@lines_count = lines_count
			@line_length = line_length
			@show_spec = show_spec
		end

		def describe
			spec = if @show_spec
				"#{@base_acronym}-#{format('%-3d', @tone)}".then do |spec|
					[print(@fg, on: @color) { " #{format('%-6s', spec)}     #{@color.srgb.hex} " }]
				end
			end
			[
				*lines.to_a.map { |line| print(@fg, on: @color) { " #{line} " } },
				*spec
			]
		end

	private

		def print(color, on:)
			bg_escape = "48;2;#{format('%d;%d;%d', *on.srgb.octets)}m"
			fg_escape = "38;2;#{format('%d;%d;%d', *color.srgb.octets)}m"
			"\x1b[#{bg_escape}\x1b[#{fg_escape}#{yield}\x1b[0m"
		end

		def lines
			return to_enum(__method__) unless block_given?

			words = @name.split(/\s+/)
			lines_yielded = 0
			loop do
				line = words.shift || ''
				while words.any? && words.first.length <= @line_length - line.length - 1
					line << ' ' << words.shift
				end
				yield line.ljust(@line_length, ' ')[..(@line_length - 1)]
				lines_yielded += 1
				break if words.empty?
				break if lines_yielded == @lines_count
			end
			while lines_yielded < @lines_count
				yield ''.ljust(@line_length, ' ')
				lines_yielded += 1
			end
		end
	end

	SwatchRow = -> *roles do
		Class.new do
			define_method(:initialize) do |base, tones:|
				@tones = tones
				roles.each_with_index do |role, i|
					instance_variable_set(:"@#{role}", base.(tones[i] / 100.0))
				end
			end

			roles.each do |role|
				define_method(role) do
					instance_variable_get(:"@#{role}").adjust_chroma
				end
			end
		end
	end

	class TierSwatchRow < SwatchRow[:color, :on_color, :container, :on_container, :color_fixed]
		def initialize(base, base_acronym:, name:, tones:)
			super(base, tones: tones)
			@base_acronym = base_acronym
			@name = name
		end

		def color
			@color.adjust_chroma(maximize: true)
		end

		def on_color
			@on_color.dechromatize(0.65)
		end

		def color_fixed
			@color_fixed.dechromatize(0.85)
		end

		def container
			@container.dechromatize(0.65)
		end

		def on_container
			@on_container.adjust_chroma(maximize: true)
		end

		def describe
			[
				Swatch.new("#{@name}", color, on_color, @base_acronym).describe,
				Swatch.new("On #{@name}", on_color, color, @base_acronym).describe,
				Swatch.new("#{@name} Container", container, on_container, @base_acronym).describe,
				Swatch.new("On #{@name} Container", on_container, container, @base_acronym).describe,
				Swatch.new("#{@name} Fixed", color_fixed, on_color, @base_acronym).describe
			].reduce(&:zip).map(&:join).join("\n")
		end
	end

	class ContainerSwatchRow < SwatchRow[:lowest, :low, :color, :high, :highest]
		def initialize(base, on_color:, tones:)
			super(base, tones: tones)
			@on_color = on_color.adjust_chroma
		end

		def describe
			[
				Swatch.new("Surface Container Lowest", lowest, @on_color, 'N').describe,
				Swatch.new("Surface Container Low", low, @on_color, 'N').describe,
				Swatch.new("Surface Container", color, @on_color, 'N').describe,
				Swatch.new("Surface Container High", high, @on_color, 'N').describe,
				Swatch.new("Surface Container Highest", highest, @on_color, 'N').describe
			].reduce(&:zip).map(&:join).join("\n")
		end
	end

	class SurfaceSwatchRow < SwatchRow[:color, :on_color, :on_color_variant, :outline, :outline_variant]
		def initialize(neutral, neutral_variant, tones:)
			@tones = tones
			[:color, :on_color].each_with_index do |role, i|
				instance_variable_set(:"@#{role}", neutral.(tones[i] / 100.0))
			end
			[:on_color_variant, :outline, :outline_variant].each_with_index do |role, i|
				instance_variable_set(:"@#{role}", neutral_variant.(tones[i + 2] / 100.0))
			end
		end

		def describe
			[
				Swatch.new("Surface", color, on_color, 'N').describe,
				Swatch.new("On Surface", on_color, color, 'N').describe,
				Swatch.new("On Surface Variant", on_color_variant, color, 'NV').describe,
				Swatch.new("Outline", outline, color, 'NV').describe,
				Swatch.new("Outline Variant", outline_variant, on_color, 'NV').describe
			].reduce(&:zip).map(&:join).join("\n")
		end
	end

	class TermSwatchRow
		def initialize(palette)
			@palette = palette
		end

		def describe
			options = { show_spec: false, lines_count: 1, line_length: 8 }
			faint = [
				Swatch.new('', @palette.term0_container, @palette.term0_container, '', **options).describe,
				Swatch.new('', @palette.term1_container, @palette.term1_container, '', **options).describe,
				Swatch.new('', @palette.term2_container, @palette.term2_container, '', **options).describe,
				Swatch.new('', @palette.term3_container, @palette.term3_container, '', **options).describe,
				Swatch.new('', @palette.term4_container, @palette.term4_container, '', **options).describe,
				Swatch.new('', @palette.term5_container, @palette.term5_container, '', **options).describe,
				Swatch.new('', @palette.term6_container, @palette.term6_container, '', **options).describe,
				Swatch.new('', @palette.term7_container, @palette.term7_container, '', **options).describe
			].reduce(&:zip).map(&:join)
			normal = [
				Swatch.new('', @palette.term0_fixed, @palette.term0_fixed, '', **options).describe,
				Swatch.new('', @palette.term1_fixed, @palette.term1_fixed, '', **options).describe,
				Swatch.new('', @palette.term2_fixed, @palette.term2_fixed, '', **options).describe,
				Swatch.new('', @palette.term3_fixed, @palette.term3_fixed, '', **options).describe,
				Swatch.new('', @palette.term4_fixed, @palette.term4_fixed, '', **options).describe,
				Swatch.new('', @palette.term5_fixed, @palette.term5_fixed, '', **options).describe,
				Swatch.new('', @palette.term6_fixed, @palette.term6_fixed, '', **options).describe,
				Swatch.new('', @palette.term7_fixed, @palette.term7_fixed, '', **options).describe
			].reduce(&:zip).map(&:join)
			bright = [
				Swatch.new('', @palette.term0, @palette.term0, '', **options).describe,
				Swatch.new('', @palette.term1, @palette.term1, '', **options).describe,
				Swatch.new('', @palette.term2, @palette.term2, '', **options).describe,
				Swatch.new('', @palette.term3, @palette.term3, '', **options).describe,
				Swatch.new('', @palette.term4, @palette.term4, '', **options).describe,
				Swatch.new('', @palette.term5, @palette.term5, '', **options).describe,
				Swatch.new('', @palette.term6, @palette.term6, '', **options).describe,
				Swatch.new('', @palette.term7, @palette.term7, '', **options).describe
			].reduce(&:zip).map(&:join)
			[faint, normal, bright].join("\n")
		end
	end

	class Palette
		def initialize(*swatches,
			           link:, link_visited:, error:, warning:, positive:, selection:,
			           term1:, term2:, term3:, term4:, term5:, term6:)
			@tier1_swatch,
			@tier2_swatch,
			@tier3_swatch,
			@tier4_swatch,
			@tier5_swatch,
			@tier6_swatch,
			@surface_swatch,
			@container_swatch = swatches
			@swatches = swatches
			@link = link
			@link_visited = link_visited
			@error = error
			@warning = warning
			@positive = positive
			@selection = selection
			@term1 = term1
			@term2 = term2
			@term3 = term3
			@term4 = term4
			@term5 = term5
			@term6 = term6
		end

		def each(&block)
			@swatches.each(&block)
		end

		def sub_role_acronym_of(color)
			case color
			when link, link_visited then '↱'
			when positive then '+'
			end
		end

		%i[tier1 tier2 tier3 tier4 tier5 tier6].each do |name|
			define_method(name) { instance_variable_get(:"@#{name}_swatch").color }
			define_method(:"on_#{name}") { instance_variable_get(:"@#{name}_swatch").on_color }
			define_method(:"#{name}_container") { instance_variable_get(:"@#{name}_swatch").container }
			define_method(:"on_#{name}_container") { instance_variable_get(:"@#{name}_swatch").on_container }
			define_method(:"#{name}_fixed") { instance_variable_get(:"@#{name}_swatch").color_fixed }
		end

		%i[
			link
			link_visited
			error
			warning
			positive
			selection
			term1
			term2
			term3
			term4
			term5
			term6
		].each do |name|
			define_method(name) do
				mapped_name = instance_variable_get(:"@#{name}")
				public_send(mapped_name)
			end

			define_method(:"on_#{name}") do
				mapped_name = instance_variable_get(:"@#{name}")
				public_send(:"on_#{mapped_name}")
			end

			define_method(:"#{name}_container") do
				mapped_name = instance_variable_get(:"@#{name}")
				public_send(:"#{mapped_name}_container")
			end

			define_method(:"on_#{name}_container") do
				mapped_name = instance_variable_get(:"@#{name}")
				public_send(:"on_#{mapped_name}_container")
			end

			define_method(:"#{name}_fixed") do
				mapped_name = instance_variable_get(:"@#{name}")
				public_send(:"#{mapped_name}_fixed")
			end
		end

		def surface
			@surface_swatch.color
		end

		alias term0_container surface

		def on_surface
			@surface_swatch.on_color
		end

		alias term7 on_surface

		def on_surface_variant
			@surface_swatch.on_color_variant
		end

		alias term7_fixed on_surface_variant

		def outline
			@surface_swatch.outline
		end

		alias term7_container outline

		def outline_variant
			@surface_swatch.outline_variant
		end

		alias term0 outline_variant

		def surface_container_lowest
			@container_swatch.lowest
		end

		def surface_container_low
			@container_swatch.low
		end

		def surface_container
			@container_swatch.color
		end

		alias term0_fixed surface_container

		def surface_container_high
			@container_swatch.high
		end

		def surface_container_highest
			@container_swatch.highest
		end
	end

	class Scheme
		def initialize(tier1:, tier2:, tier3:, tier4:, tier5:, tier6:,
			           neutral:, neutral_variant:, link:, link_visited:,
			           error:, warning:, positive:, selection: :tier1,
			           term1: :tier6, term2: :positive, term3: :warning,
			           term4: :link, term5: :link_visited, term6: :tier4)
			aliases_refs = %i[tier1 tier2 tier3 tier4 tier5 tier6]
			raise "link color must correspond to one of: #{aliases_refs.join(', ')}" if !aliases_refs.include?(link)
			raise "link_visited color must correspond to one of: #{aliases_refs.join(', ')}" if !aliases_refs.include?(link_visited)
			raise "error color must correspond to one of: #{aliases_refs.join(', ')}" if !aliases_refs.include?(error)
			raise "warning color must correspond to one of: #{aliases_refs.join(', ')}" if !aliases_refs.include?(warning)
			raise "positive color must correspond to one of: #{aliases_refs.join(', ')}" if !aliases_refs.include?(positive)
			raise "selection color must correspond to one of: #{aliases_refs.join(', ')}" if !aliases_refs.include?(selection)

			@tier1, @tier2, @tier3, @tier4, @tier5, @tier6 = [tier1, tier2, tier3, tier4, tier5, tier6]
			@link, @link_visited, @error, @warning, @positive, @selection = [link, link_visited, error, warning, positive, selection]
			@term1, @term2, @term3, @term4, @term5, @term6 = [term1, term2, term3, term4, term5, term6]
			@neutral = neutral
			@neutral_variant = neutral_variant

			inc = 3
			max = 100
			gap = 5 * inc
			variant_contrast = 10
			fixed_gap = 29
			max_contrast = 2*fixed_gap
			highest_light = max - gap
			fixed = highest_light - fixed_gap
			highest_dark = highest_light - max_contrast
			color_light = max - max_contrast
			container_light = highest_light - 5
			min = highest_dark - gap
			color_dark = min + max_contrast
			container_dark = highest_dark + 5

			@tones = {
				light: {
					tier: [
						color_light,                    # color
						color_light + max_contrast,     # on-color
						container_light,                # container
						container_light - max_contrast, # on-container
						fixed                           # fixed color
					],
					container: [
						max,          # lowest
						max - 2*inc,  # low
						max - 3*inc,  # medium
						max - 4*inc,  # high
						highest_light # highest
					],
					surface: [
						max - inc,                                       # color
						highest_light - max_contrast,                    # on-color
						highest_light - max_contrast + variant_contrast, # on-color variant
						highest_light - fixed_gap,                       # outline
						highest_light - fixed_gap + variant_contrast     # outline variant
					]
				},
				dark: {
					tier: [
						color_dark,
						color_dark - max_contrast,
						container_dark,
						container_dark + max_contrast,
						fixed
					],
					container: [
						highest_dark - 5*inc,
						highest_dark - 3*inc,
						highest_dark - 2*inc,
						highest_dark - inc,
						highest_dark
					],
					surface: [
						highest_dark - 4*inc,
						highest_dark + max_contrast,
						highest_dark + max_contrast - variant_contrast,
						highest_dark + fixed_gap,
						highest_dark + fixed_gap - variant_contrast,
					]
				}
			}
		end

		def light
			@light ||= compute_palette(:light)
		end

		def dark
			@dark ||= compute_palette(:dark)
		end

		def print
			light.each { |swatch| puts swatch.describe }
			puts TermSwatchRow.new(light).describe
			dark.each { |swatch| puts swatch.describe }
			puts TermSwatchRow.new(dark).describe
		end

		private

		def compute_palette(mode)
			tones = @tones[mode]
			SurfaceSwatchRow.new(@neutral, @neutral_variant, tones: tones[:surface]).then do |surface_swatch|
				Palette.new(
					TierSwatchRow.new(@tier1, tones: tones[:tier], name: 'Tier 1', base_acronym: 'T1'),
					TierSwatchRow.new(@tier2, tones: tones[:tier], name: 'Tier 2', base_acronym: 'T2'),
					TierSwatchRow.new(@tier3, tones: tones[:tier], name: 'Tier 3', base_acronym: 'T3'),
					TierSwatchRow.new(@tier4, tones: tones[:tier], name: 'Tier 4', base_acronym: 'T4'),
					TierSwatchRow.new(@tier5, tones: tones[:tier], name: 'Tier 5', base_acronym: 'T5'),
					TierSwatchRow.new(@tier6, tones: tones[:tier], name: 'Tier 6', base_acronym: 'T6'),
					surface_swatch,
					ContainerSwatchRow.new(@neutral, on_color: surface_swatch.on_color, tones: tones[:container]),
					link: @link,
					link_visited: @link_visited,
					error: @error,
					warning: @warning,
					positive: @positive,
					selection: @selection,
					term1: @term1,
					term2: @term2,
					term3: @term3,
					term4: @term4,
					term5: @term5,
					term6: @term6
				)
			end
		end
	end

	Substance = Scheme.new(
		tier1: OKLrch[0, 0, 340],
		tier2: OKLrch[0, 0, 285],
		tier3: OKLrch[0, 0, 230],
		tier4: OKLrch[0, 0, 160],
		tier5: OKLrch[0, 0, 95],
		tier6: OKLrch[0, 0, 30],
		neutral: OKLrch[0, 0.01, 340],
		neutral_variant: OKLrch[0, 0.02, 30],
		link: :tier3,
		link_visited: :tier1,
		warning: :tier5,
		positive: :tier4,
		term4: :tier2,
		term6: :tier3,
		error: :tier6
	)

	Substance.print if __FILE__ == $0
end

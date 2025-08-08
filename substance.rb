require 'matrix'

module Substance
	# Conversion matrices and formulas from
	# https://drafts.csswg.org/css-color-4/#color-conversion-code

	LMStoXYZ = Matrix[
		[ 1.2268798733741557,  -0.5578149965554813,  0.28139105017721583],
		[-0.04057576262431372,  1.1122868293970594, -0.07171106666151701],
		[-0.07637294974672142, -0.4214933239627914,  1.5869240244272418 ],
	]

	OKLabtoLMS = Matrix[
		[0.99999999845051981432, 0.39633779217376785678,   0.21580375806075880339 ],
		[1.0000000088817607767, -0.1055613423236563494,   -0.063854174771705903402],
		[1.0000000546724109177, -0.089484182094965759684, -1.2914855378640917399  ],
	]

	XYZtoLinearSRGB = Matrix[
		[ 3.2409699419045226,  -1.537383177570094,  -0.4986107602930034 ],
		[-0.9692436362808796,   1.8759675015077202,  0.04155505740717559],
		[ 0.05563007969699366, -0.20397695888897652, 1.0569715142428786 ],
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

			define_method(:to_s) do
				"#{self.class.name}(#{Vector[*self]})"
			end
		end
	end

	class OKLch < Channels[:l, :c, :h]
		def initialize(l, c, h)
			h %= 360
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
	# https://gist.github.com/facelessuser/0235cb0fecc35c4e06a8195d5e18947b
	# https://facelessuser.github.io/coloraide/playground/?notebook=https%3A%2F%2Fgist.githubusercontent.com%2Ffacelessuser%2F0235cb0fecc35c4e06a8195d5e18947b%2Fraw%2F3ca56c388735535de080f1974bfa810f4934adcd%2Fexploring-tonal-palettes.md
	class OKLrch < Channels[:l, :c, :h]
		# Values proposed by Björn Ottosson to match L*a*b:
		K1 = 0.206
		K2 = 0.03

		# Values proposed by facelessuser (creator of ColorAide lib) to better match HCT:
		# K1 = 0.173
		# K2 = 0.004

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

		def scale_max_srgb_chroma(factor)
			lr, c, h = limit_srgb_chroma(force_maximization: true).to_a
			c *= factor.clamp(0, 1)
			self.class.new(lr, c, h)
		end

		def limit_srgb_chroma(force_maximization: false)
			return self if srgb.in_gamut? && !force_maximization

			if srgb.in_gamut?
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
			while hi - lo > ε
				c = (hi + lo) / 2
				if OKLab.from_lch(@l, c, @h).srgb.in_gamut?
					lo = c
				else
					hi = c
				end
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
			hr = Math.atan2(b, a)
			hr += 2 * Math::PI if hr.negative?
			OKLch.new(@l, Math.sqrt(a * a + b * b), hr * 180 / Math::PI)
		end

		def oklab
			self
		end

	private

		def xyz
			lms = OKLabtoLMS * Vector[l, a, b]
			XYZ.new(*(LMStoXYZ * lms.map { |c| c**3 }))
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
			@hex ||= format('#%02x%02x%02x', *octets)
		end

		def octets
			clamped.map { |c| (c * 255).round }
		end

		def in_gamut?
			ε = 0.000005
			[@r, @g, @b].all? { |c| c >= -ε && c <= 1 + ε }
		end

		def wcag_contrast(other)
			l2, l1 = [relative_luminance, other.relative_luminance].sort
			(l1 + 0.05) / (l2 + 0.05)
		end

	private

		def clamped
			to_a.map { |c| c.clamp(0, 1) }
		end
	end

	class Swatch
		def initialize(base_name, description, relative_light)
			@base_name = base_name
			@description = description
			@relative_light = relative_light
			@base_acronym =
				case base_name
				when :neutral then 'N'
				when :neutral_variant then 'NV'
				else
					"T#{base_name.to_s.gsub(/\D/, '')}"
				end
		end

		def color(color_refs, surface_lightness, chroma_factor = nil)
			base_color = color_refs[@base_name]
			signal = surface_lightness < 50 ? 1 : -1
			light = surface_lightness + signal * @relative_light
			color = base_color.(light / 100.0)
			if chroma_factor
				color.scale_max_srgb_chroma(chroma_factor)
			else
				color.limit_srgb_chroma
			end
		end

		def describe(color, fg:, bg:, strict: false)
			if strict
				final_bg, final_fg = bg, fg
			else
				final_fg = (fg.l - color.l).abs >= (bg.l - color.l).abs ? fg : bg
				final_bg = (fg.l - color.l).abs < (bg.l - color.l).abs ? fg : bg
			end
			spec = "#{@base_acronym}-#{format('%-3d', color.l * 100)}".then do |spec|
				print(final_fg, on: color) { " #{format('%-6s', spec)}     #{color.srgb.hex} " }
			end
			description_1, description_2 = lines([18, 8]).to_a
			contrast_fg = color.srgb.wcag_contrast(final_fg.srgb)
			contrast_bg = color.srgb.wcag_contrast(final_bg.srgb)
			contrast_fg, contrast_bg = [contrast_fg, contrast_bg].map do |c|
				format('%.1f', c).rjust(4, ' ')
			end
			[
				print(final_fg, on: color) { " #{description_1} " },
				print(final_fg, on: color) { " #{description_2} " } +
				print(final_bg, on: color) { "#{contrast_bg} " } +
				print(final_fg, on: color) { "#{contrast_fg} " },
				spec
			]
		end

	private

		def print(color, on:)
			bg_escape = "48;2;#{format('%d;%d;%d', *on.srgb.octets)}m"
			fg_escape = "38;2;#{format('%d;%d;%d', *color.srgb.octets)}m"
			"\x1b[#{bg_escape}\x1b[#{fg_escape}#{yield}\x1b[0m"
		end

		def lines(line_lengths)
			return to_enum(__method__, line_lengths) unless block_given?

			words = @description.split(/\s+/)
			lines_yielded = 0
			line_lengths.size.times do |i|
				line_length = line_lengths[i]
				line = words.shift || ''
				while words.any? && words.first.length <= line_length - line.size - 1
					line << ' ' << words.shift
				end
				yield line.ljust(line_length, ' ')
			end
		end
	end

	class Palette
		class << self
			def define_color(name, &block)
				define_method(name) do
					ivar = :"@#{name}"
					return instance_variable_get(ivar) if instance_variable_defined?(ivar)

					instance_variable_set(ivar, instance_eval(&block))
				end
			end
		end

		def initialize(color_refs, swatch_rows, surface_lightness, **roles)
			@color_refs = color_refs
			@swatch_rows = swatch_rows
			@swatches = swatch_rows.reduce(&:merge)
			@surface_lightness = surface_lightness
			roles.each do |name, value|
				instance_variable_set(:"@#{name}", value)
			end
		end

		(1..6).each do |n|
			name = :"tier#{n}_container"
			define_color(name) do
				base = @swatches[name].color(@color_refs, @surface_lightness, 0.5)
				signal = @surface_lightness < 50 ? -1 : 1
				while base.srgb.wcag_contrast(on_surface_intense.srgb) < 6.5
					base = base.(base.l + (signal * 0.01))
				end
				base
			end
		end

		(1..6).each do |n|
			name = :"tier#{n}_mild"
			define_color(name) do
				mid_contrast_color(
					@swatches[name].color(@color_refs, @surface_lightness, 0.7),
					surface,
					on_surface
				)
			end
		end

		(1..6).each do |n|
			name = :"tier#{n}"
			define_color(name) do
				base = @swatches[name].color(@color_refs, @surface_lightness, 0.85)
				signal = @surface_lightness < 50 ? 1 : -1
				while base.srgb.wcag_contrast(surface.srgb) < 6.5
					base = base.(base.l + (signal * 0.01))
				end
				base
			end
		end

		def outline
			base = @swatches[:outline].color(@color_refs, @surface_lightness)
			signal = @surface_lightness < 50 ? 1 : -1
			while base.srgb.wcag_contrast(surface.srgb) < 3.5
				base = base.(base.l + (signal * 0.01))
			end
			base
		end

		def outline_mild
			base = @swatches[:outline_mild].color(@color_refs, @surface_lightness)
			signal = @surface_lightness < 50 ? 1 : -1
			while base.srgb.wcag_contrast(surface.srgb) < 2.5
				base = base.(base.l + (signal * 0.01))
			end
			base
		end

		def on_surface_mild
			base = @swatches[:on_surface_mild].color(@color_refs, @surface_lightness)
			signal = @surface_lightness < 50 ? 1 : -1
			while base.srgb.wcag_contrast(surface.srgb) < 6.5
				base = base.(base.l + (signal * 0.01))
			end
			base
		end

		%i[
			on_surface
			on_surface_term
			on_surface_intense
			surface_container_lowest
			surface
			surface_container_low
			surface_container
			surface_container_high
			surface_container_highest
		].each do |name|
			define_color(name) do
				@swatches[name].color(@color_refs, @surface_lightness)
			end
		end

		%i[
			link
			link_visited
			error
			warning
			positive
			active
			highlight
			selection
			secondary_selection
			attribute
			keyword
			type
			function
			value
			string
			variable
			meta
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

			define_method(:"#{name}_container") do
				mapped_name = instance_variable_get(:"@#{name}")
				public_send(:"#{mapped_name}_container")
			end

			define_method(:"#{name}_mild") do
				mapped_name = instance_variable_get(:"@#{name}")
				public_send(:"#{mapped_name}_mild")
			end
		end

		alias term0 outline
		alias term0_mild surface
		alias term0_container surface

		alias term7 on_surface_intense
		alias term7_mild on_surface
		alias term7_container on_surface_mild

		def describe
			@swatch_rows.map do |swatch_row|
				swatch_row.map do |name, swatch|
					fg, strict =
						if name =~ /tier\d_mild/
							[on_surface, true]
						elsif name =~ /tier\d_container/
							[on_surface_intense, true]
						else
							[on_surface, false]
						end
					color = public_send(name)
					swatch.describe(color, bg: surface, fg:, strict:)
				end.reduce(&:zip).map(&:join).join("\n") + "\n"
			end.join
		end

	private

		def mid_contrast_color(base, bg, fg)
			ε = 0.01
			attempts = 20
			diff = base.srgb.wcag_contrast(bg.srgb) - base.srgb.wcag_contrast(fg.srgb)
			if diff > 0
				lo = bg.l
				hi = base.l
			else
				hi = fg.l
				lo = base.l
			end
			while diff.abs > ε
				if diff > 0
					hi = base.l
				else
					lo = base.l
				end
				base = base.((lo + hi) / 2.0)
				diff = base.srgb.wcag_contrast(bg.srgb) - base.srgb.wcag_contrast(fg.srgb)
			end
			base
		end
	end

	class Scheme
		def initialize(tier1:, tier2:, tier3:, tier4:, tier5:, tier6:,
			             neutral:, neutral_variant:, link:, link_visited:,
			             error:, warning:, positive:, active:, highlight: :tier3,
			             selection: :tier1, secondary_selection: :tier2,
			             attribute: :tier4, keyword: :tier2, type: :tier3, function: :tier3,
			             value: :tier1, string: :tier1, variable: :tier5, meta: :tier6,
			             term1: :error, term2: :positive, term3: :warning,
			             term4: :link, term5: :link_visited, term6: :active)
			tier_refs = %i[tier1 tier2 tier3 tier4 tier5 tier6]
			raise "link color must correspond to one of: #{tier_refs.join(', ')}" if !tier_refs.include?(link)
			if !tier_refs.include?(link_visited)
				raise "link_visited color must correspond to one of: #{tier_refs.join(', ')}"
			end
			raise "error color must correspond to one of: #{tier_refs.join(', ')}" if !tier_refs.include?(error)
			raise "warning color must correspond to one of: #{tier_refs.join(', ')}" if !tier_refs.include?(warning)
			raise "positive color must correspond to one of: #{tier_refs.join(', ')}" if !tier_refs.include?(positive)
			raise "active color must correspond to one of: #{tier_refs.join(', ')}" if !tier_refs.include?(active)
			raise "highlight color must correspond to one of: #{tier_refs.join(', ')}" if !tier_refs.include?(highlight)
			raise "selection color must correspond to one of: #{tier_refs.join(', ')}" if !tier_refs.include?(selection)
			if !tier_refs.include?(secondary_selection)
				raise "secondary_selection color must correspond to one of: #{tier_refs.join(', ')}"
			end
			raise "attribute color must correspond to one of: #{tier_refs.join(', ')}" if !tier_refs.include?(attribute)
			raise "keyword color must correspond to one of: #{tier_refs.join(', ')}" if !tier_refs.include?(keyword)
			raise "type color must correspond to one of: #{tier_refs.join(', ')}" if !tier_refs.include?(type)
			raise "function color must correspond to one of: #{tier_refs.join(', ')}" if !tier_refs.include?(function)
			raise "value color must correspond to one of: #{tier_refs.join(', ')}" if !tier_refs.include?(value)
			raise "string color must correspond to one of: #{tier_refs.join(', ')}" if !tier_refs.include?(string)
			raise "variable color must correspond to one of: #{tier_refs.join(', ')}" if !tier_refs.include?(variable)
			raise "meta color must correspond to one of: #{tier_refs.join(', ')}" if !tier_refs.include?(meta)

			@color_refs = {
				tier1:, tier2:, tier3:, tier4:, tier5:, tier6:,
				neutral:, neutral_variant:
			}

			@roles = {
				link:, link_visited:,
				error:, positive:, warning:, highlight:, active:,
				selection:, secondary_selection:,
				attribute:, keyword:, type:, function:, value:, string:, variable:, meta:,
				term1:, term2:, term3:, term4:, term5:, term6:
			}

			surface_column = {
				surface_container_lowest: Swatch.new(:neutral, 'Surface Container Lowest', -3),
				surface: Swatch.new(:neutral, 'Surface', 0),
				surface_container_low: Swatch.new(:neutral, 'Surface Container Low', 3),
				surface_container: Swatch.new(:neutral, 'Surface Container', 6),
				surface_container_high: Swatch.new(:neutral, 'Surface Container High', 9),
				surface_container_highest: Swatch.new(:neutral, 'Surface Container Highest', 12)
			}.to_a

			on_surface_column = {
				outline_mild: Swatch.new(:neutral_variant, 'Outline Mild', 30),
				outline: Swatch.new(:neutral_variant, 'Outline', 40),
				on_surface_mild: Swatch.new(:neutral_variant, 'On Surface Mild', 55),
				on_surface: Swatch.new(:neutral_variant, 'On Surface', 70),
				on_surface_term: Swatch.new(:neutral_variant, 'On Surface Term', 76),
				on_surface_intense: Swatch.new(:neutral_variant, 'On Surface Intense', 80),
			}.to_a

			@swatch_rows = (1..6).map do |n|
				on_surface_item_name, on_surface_item_swatch = on_surface_column[n - 1]
				surface_item_name, surface_item_swatch = surface_column[n - 1]
				{
					surface_item_name => surface_item_swatch,
					on_surface_item_name => on_surface_item_swatch,
					"tier#{n}_container": Swatch.new(:"tier#{n}", "Tier #{n} Container", 22),
					"tier#{n}_mild": Swatch.new(:"tier#{n}", "Tier #{n} Mild", 38),
					"tier#{n}": Swatch.new(:"tier#{n}", "Tier #{n}", 55),
				}
			end
		end

		def light
			@light ||= Palette.new(@color_refs, @swatch_rows, 90, **@roles)
		end

		def dark
			@dark ||= Palette.new(@color_refs, @swatch_rows, 15, **@roles)
		end

		def print
			puts light.describe
			puts dark.describe
		end
	end

	Substance = Scheme.new(
		tier1: OKLrch[0, 0, 340],
		tier2: OKLrch[0, 0, 285],
		tier3: OKLrch[0, 0, 230],
		tier4: OKLrch[0, 0, 160],
		tier5: OKLrch[0, 0, 95],
		tier6: OKLrch[0, 0, 30],
		neutral: OKLrch[0, 0.01, 95],
		neutral_variant: OKLrch[0, 0.025, 30],
		active: :tier3,
		attribute: :tier3,
		error: :tier6,
		keyword: :tier1,
		link: :tier3,
		link_visited: :tier1,
		meta: :tier6,
		positive: :tier4,
		string: :tier2,
		value: :tier4,
		warning: :tier5,
		term4: :tier2,
		highlight: :tier5,
	)

	Substance.print if __FILE__ == $0
end

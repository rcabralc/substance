require 'matrix'

module Substance
	# Conversion matrices and formulas from
	# https://drafts.csswg.org/css-color-4/#color-conversion-code

	LMStoXYZ = Matrix[
		[ 1.2268798758459243, -0.5578149944602171,  0.2813910456659647],
		[-0.0405757452148008,  1.1122868032803170, -0.0717110580655164],
		[-0.0763729366746601, -0.4214933324022432,  1.5869240198367816]
	]

	OKLabtoLMS = Matrix[
		[1.0000000000000000,  0.3963377773761749,  0.2158037573099136],
		[1.0000000000000000, -0.1055613458156586, -0.0638541728258133],
		[1.0000000000000000, -0.0894841775298119, -1.2914855480194092]
  ]

	XYZtoLinearSRGB = Matrix[
		[ 3.2409699419045226,  -1.537383177570094,  -0.4986107602930034 ],
		[-0.9692436362808796,   1.8759675015077202,  0.04155505740717559],
		[ 0.05563007969699366, -0.20397695888897652, 1.0569715142428786 ],
	]

	LinearSRGBtoXYZ = Matrix[
		[0.41239079926595934, 0.357584339383878,   0.1804807884018343 ],
		[0.21263900587151027, 0.715168678767756,   0.07219231536073371],
		[0.01933081871559182, 0.11919477979462598, 0.9505321522496607 ],
	]

	XYZtoLMS = Matrix[
		[0.8190224379967030, 0.3619062600528904, -0.1288737815209879],
		[0.0329836539323885, 0.9292868615863434,  0.0361446663506424],
		[0.0481771893596242, 0.2642395317527308,  0.6335478284694309],
	]

	LMStoOKLab = Matrix[
		[0.2104542683093140,  0.7936177747023054, -0.0040720430116193],
		[1.9779985324311684, -2.4285922420485799,  0.4505937096174110],
		[0.0259040424655478,  0.7827717124575296, -0.8086757549230774],
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

			define_method(:deconstruct_keys) do |keys|
				keys.to_h do |key|
					[key, public_send(key)]
				end
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

		def scale_max_srgb_chroma(factor = 1.0)
			limit_srgb_chroma(force_maximization: true, factor:)
		end

		def limit_srgb_chroma(force_maximization: false, factor: nil)
			unless factor.nil?
				force_maximization = true
				factor = factor.clamp(0, 1)
			end

			return self if srgb.in_gamut? && !force_maximization

			if srgb.in_gamut?
				# Increase chroma while conversion stays in SRGB gamut within a certain tolerance.
				hi = 0.5
				lo = c
			else
				# Reduce chroma until conversion reaches SRGB gamut within a certain tolerance.
				# Adapted from https://github.com/LeaVerou/css.land/blob/master/lch/lch.js
				hi = c
				lo = 0
			end

			ε = 1e-4
			while hi - lo > ε
				new_c = (hi + lo) / 2
				if call(nil, new_c).srgb.in_gamut?
					lo = new_c
				else
					hi = new_c
				end
			end

			call(nil, new_c * (factor || 1))
		end

		def srgb
			@srgb ||= oklab.srgb
		end

		def ΔE(*, **)
			oklab.ΔE(*, **)
		end

		def oklab
			@oklab ||= OKLab.from_lch(l, c, h)
		end

		def self.from_hex(hex)
			OKLab.from_hex(hex).oklch
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
	class OKLrch < Channels[:lr, :c, :h]
		# Values proposed by Björn Ottosson to match L*a*b:
		K1 = 0.206
		K2 = 0.03

		# Values proposed by facelessuser (creator of ColorAide lib) to better match HCT:
		# K1 = 0.173
		# K2 = 0.004

		K3 = (1 + K1) / (1 + K2)

		def initialize(lr, c, h)
			super(lr, c, h)
			l = lr * (lr + K1) / (lr + K2) / K3
			@oklch = OKLch.new(l, c, h)
		end

		def call(lr = nil, c = nil, h = nil)
			lr ||= @lr
			c ||= @c
			h ||= @h
			self.class.new(lr, c, h)
		end

		def scale_max_srgb_chroma(factor = 1.0)
			self.class.from_oklch(@oklch.scale_max_srgb_chroma(factor))
		end

		def limit_srgb_chroma(force_maximization: false)
			return self if srgb.in_gamut? && !force_maximization

			self.class.from_oklch(@oklch.limit_srgb_chroma(force_maximization:))
		end

		def ΔE(*, **)
			oklab.ΔE(*, **)
		end

		def srgb
			@oklch.srgb
		end

		def oklab
			@oklch.oklab
		end

		def inspect
			lr = format('%3.1f', @lr)
			c = format('%3.1f', @c)
			h = format('%5.1f', @h)
			color = "\x1b[48;2;#{format('%d;%d;%d', *srgb.octets)}m   \x1b[0m"
			%[OKLrch[#{lr},#{c},#{h}] #{color}]
		end

		def self.from_hex(hex)
			from_oklch(OKLab.from_hex(hex).oklch)
		end

		def self.from_oklch(oklch)
			l, c, h = *oklch
			new(lr_from_l(l), c, h)
		end

		def self.lr_from_l(l)
			(K3 * l - K1 + Math.sqrt((K3 * l - K1)**2 + 4 * K2 * K3 * l)) / 2
		end
	end

	class OKLab < Channels[:l, :a, :b]
		def srgb
			xyz.srgb
		end

		def self.from_lch(l, c, h)
			new(l, c * Math.cos(h * Math::PI / 180), c * Math.sin(h * Math::PI / 180))
		end

		def self.from_hex(hex)
			hex = hex.gsub(/^#/, '')
			rgb = Vector[*hex.chars.each_slice(2).map { |s| s.join.to_i(16) / 255.0 }]
			linear_rgb = rgb.map do |c|
				if c.abs <= 0.04045
					c / 12.92
				else
					(c < 0 ? -1 : 1) * (((c.abs + 0.055) / 1.055)**2.4)
				end
			end
			xyz = LinearSRGBtoXYZ * linear_rgb
			lms = XYZtoLMS * xyz
			OKLab[*(LMStoOKLab * lms.map { |c| c**(1.0 / 3) })]
		end

		def oklch
			hr = Math.atan2(b, a)
			hr += 2 * Math::PI if hr.negative?
			OKLch.new(@l, Math.sqrt(a * a + b * b), hr * 180 / Math::PI)
		end

		def oklab
			self
		end

		def ΔE(other, mode: :ok)
			case mode
			when :ok
				other.oklab => { a: other_a, b: other_b, l: other_l }
				Math.sqrt((a - other_a)**2 + (b - other_b)**2 + (l - other_l)**2)
			when :ciede2000
				# CIEDE2000 implementation based on the formula from Wikipedia
				# https://en.wikipedia.org/wiki/Color_difference#CIEDE2000
				# and
				# https://drafts.csswg.org/css-color-4/#color-conversion-code
				# and
				# https://michel-leonard.github.io/ciede2000-color-matching/lab-color-calculator.html
				l1, a1, b1 = *cielab
				l2, a2, b2 = *other.oklab.cielab

				c1 = Math.sqrt(a1**2 + b1**2)
				c2 = Math.sqrt(a2**2 + b2**2)
				c_bar = (c1 + c2) / 2.0

				g = 0.5 * (1 - Math.sqrt(c_bar**7 / (c_bar**7 + 25**7)))
				a1_prime = (1 + g) * a1
				a2_prime = (1 + g) * a2

				c1_prime = Math.sqrt(a1_prime**2 + b1**2)
				c2_prime = Math.sqrt(a2_prime**2 + b2**2)

				δL = l2 - l1
				δC = c2_prime - c1_prime

				h1_prime = c1_prime == 0 ? 0 : Math.atan2(b1, a1_prime)
				h2_prime = c2_prime == 0 ? 0 : Math.atan2(b2, a2_prime)

				h1_prime += 2 * Math::PI if h1_prime < 0
				h2_prime += 2 * Math::PI if h2_prime < 0

				h1_prime *= 180 / Math::PI
				h2_prime *= 180 / Math::PI
				hsum_prime = h1_prime + h2_prime
				hdiff_prime = h2_prime - h1_prime

				δh_prime =
					if (c1_prime * c2_prime == 0)
						0
					elsif hdiff_prime.abs <= 180
						hdiff_prime
					elsif hdiff_prime > 180
						hdiff_prime - 360
					else
						hdiff_prime + 360
					end

				δH = 2 * Math.sqrt(c1_prime * c2_prime) * Math.sin(δh_prime * Math::PI / 180 / 2.0)

				l_bar = (l1 + l2) / 2.0
				c_bar_prime = (c1_prime + c2_prime) / 2.0

				h_bar =
					if (c1_prime * c2_prime == 0)
						hsum_prime
					elsif hdiff_prime.abs <= 180
						hsum_prime / 2.0
					elsif hsum_prime < 360
						(hsum_prime + 360) / 2.0
					else
						(hsum_prime - 360) / 2.0
					end

				lsq = (l_bar - 50)**2
				sl = 1 + (0.015 * lsq) / Math.sqrt(20 + lsq)
				sc = 1 + 0.045 * c_bar_prime

				t = 1.0
				t -= 0.17 * Math.cos((h_bar - 30) * Math::PI / 180)
				t += 0.24 * Math.cos(2 * h_bar * Math::PI / 180)
				t += 0.32 * Math.cos((3 * h_bar + 6) * Math::PI / 180)
				t -= 0.20 * Math.cos((4 * h_bar - 63) * Math::PI / 180)

				sh = 1 + 0.015 * c_bar_prime * t

				θ = 60 * Math.exp(-1 * ((h_bar - 275) / 25.0)**2)
				rc = -2 * Math.sqrt(c_bar_prime**7 / (c_bar_prime**7 + 25**7))
				rt = rc * Math.sin(θ * Math::PI / 180)

				kl = 1
				kc = 1
				kh = 1
				term1 = δL / (kl * sl)
				term2 = δC / (kc * sc)
				term3 = δH / (kh * sh)

				Math.sqrt(term1**2 + term2**2 + term3**2 + rt * term2 * term3)
			end
		end

		def cielab
			xyz.cielab
		end

	private

		def xyz
			lms = OKLabtoLMS * Vector[l, a, b]
			XYZ.new(*(LMStoXYZ * lms.map { |c| c**3 }))
		end
	end

	CIELAB = Struct.new(:l, :a, :b)

	class XYZ < Channels[:x, :y, :z]
		def srgb
			linear_srgb.srgb
		end

		def cielab
			xn, yn, zn = [0.9504, 1.0, 1.0888]

			fx = ->(t) { t > (6.0/29.0)**3 ? t**(1.0/3.0) : (1.0/3.0) * (29.0/6.0)**2 * t + 16.0/116.0 }

			l = 116.0 * fx.(y/yn) - 16.0
			a = 500.0 * (fx.(x/xn) - fx.(y/yn))
			b = 200.0 * (fx.(y/yn) - fx.(z/zn))

			CIELAB.new(l, a, b)
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

		def color(color_refs, surface_lightness)
			base_color = color_refs[@base_name]
			signal = surface_lightness < 50 ? 1 : -1
			light = surface_lightness + signal * @relative_light
			base_color.call(light / 100.0).limit_srgb_chroma
		end

		def describe(color, fg:, bg:, strict: false)
			if strict
				final_bg = bg
				final_fg = fg
			else
				final_fg = (fg.lr - color.lr).abs >= (bg.lr - color.lr).abs ? fg : bg
				final_bg = (fg.lr - color.lr).abs < (bg.lr - color.lr).abs ? fg : bg
			end
			spec = "#{@base_acronym}-#{format('%-3d', color.lr * 100)}".then do |spec|
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
			line_lengths.size.times do |i|
				line_length = line_lengths[i]
				line = words.shift || ''
				line << ' ' << words.shift while words.any? && words.first.length <= line_length - line.size - 1
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
				chroma_factor = 0.5
				base = @swatches[name].color(@color_refs, @surface_lightness).scale_max_srgb_chroma(chroma_factor)
				signal = @surface_lightness < 50 ? -1 : 1
				while base.srgb.wcag_contrast(on_surface.srgb) < 4.5
					base = base.call(base.lr + (signal * 0.001)).scale_max_srgb_chroma(chroma_factor)
				end
				base
			end
		end

		(1..6).each do |n|
			name = :"tier#{n}_mild"
			define_color(name) do
				chroma_factor = 0.8
				base = @swatches[name].color(@color_refs, @surface_lightness).scale_max_srgb_chroma(chroma_factor)
				mid_contrast_color(base, surface, on_surface_intense, chroma_factor:)
			end
		end

		(1..6).each do |n|
			name = :"tier#{n}"
			define_color(name) do
				base = @swatches[name].color(@color_refs, @surface_lightness).scale_max_srgb_chroma
				signal = @surface_lightness < 50 ? 1 : -1
				while base.srgb.wcag_contrast(surface.srgb) < 4.5
					base = base.call(base.l + (signal * 0.001)).scale_max_srgb_chroma
				end
				base
			end
		end

		def outline
			base = @swatches[:outline].color(@color_refs, @surface_lightness)
			signal = @surface_lightness < 50 ? 1 : -1
			base = base.call(base.lr + (signal * 0.001)) while base.srgb.wcag_contrast(surface.srgb) < 3.5
			base
		end

		def on_surface_mild
			base = @swatches[:on_surface_mild].color(@color_refs, @surface_lightness)
			signal = @surface_lightness < 50 ? 1 : -1
			base = base.call(base.lr + (signal * 0.01)) while base.srgb.wcag_contrast(surface.srgb) < 4.5
			base
		end

		%i[
			on_surface
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

		alias outline_1 outline
		alias on_surface_1 on_surface

		def describe
			@swatch_rows.map do |swatch_row|
				swatch_row.map do |name, swatch|
					bg, fg, strict =
						if name =~ /tier\d_mild/
							[surface, on_surface_intense, true]
						elsif name =~ /tier\d_container/
							[surface, on_surface, true]
						elsif name =~ /tier\d/
							[on_surface, surface, true]
						else
							[surface, on_surface, false]
						end
					color = public_send(name)
					swatch.describe(color, bg:, fg:, strict:)
				end.reduce(&:zip).map(&:join).join("\n") + "\n"
			end.join
		end

	private

		def mid_contrast_color(base, bg, fg, chroma_factor: nil)
			ε = 0.01
			diff = base.srgb.wcag_contrast(bg.srgb) - base.srgb.wcag_contrast(fg.srgb)
			if diff > 0
				lo = bg.lr
				hi = base.lr
			else
				hi = fg.lr
				lo = base.lr
			end
			while diff.abs > ε
				if diff > 0
					hi = base.lr
				else
					lo = base.lr
				end
				base = base.call((lo + hi) / 2.0)
				base = base.scale_max_srgb_chroma(chroma_factor) if chroma_factor
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

			on_surface_row = {
				outline: Swatch.new(:neutral_variant, 'Outline', 35),
				on_surface_mild: Swatch.new(:neutral_variant, 'On Surface Mild', 50),
				on_surface: Swatch.new(:neutral_variant, 'On Surface', 65),
				on_surface_intense: Swatch.new(:neutral_variant, 'On Surface Intense', 73),
			}

			@swatch_rows = (1..6).map do |n|
				surface_item_name, surface_item_swatch = surface_column[n - 1]
				{
					surface_item_name => surface_item_swatch,
					"tier#{n}_container": Swatch.new(:"tier#{n}", "Tier #{n} Container", 20),
					"tier#{n}_mild": Swatch.new(:"tier#{n}", "Tier #{n} Mild", 35),
					"tier#{n}": Swatch.new(:"tier#{n}", "Tier #{n}", 50)
				}
			end + [on_surface_row]
		end

		def light
			@light ||= Palette.new(@color_refs, @swatch_rows, 92, **@roles)
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

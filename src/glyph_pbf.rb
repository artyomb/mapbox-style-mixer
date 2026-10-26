require 'google/protobuf'
require 'google/protobuf/descriptor_pb'

module GlyphPbf
  class InvalidData < StandardError; end

  def self.field(name, number, type, label = :LABEL_REQUIRED, type_name = nil)
    field = Google::Protobuf::FieldDescriptorProto.new(name: name, number: number, type: type, label: label)
    field.type_name = type_name if type_name
    field
  end
  private_class_method :field

  # Schema: https://github.com/mapbox/node-fontnik/blob/master/proto/glyphs.proto
  pool = Google::Protobuf::DescriptorPool.new
  pool.add_serialized_file(Google::Protobuf::FileDescriptorProto.new(
    name: 'glyphs.proto', syntax: 'proto2', package: 'llmr.glyphs', message_type: [
      Google::Protobuf::DescriptorProto.new(name: 'glyph', field: [
        field('id', 1, :TYPE_UINT32), field('bitmap', 2, :TYPE_BYTES, :LABEL_OPTIONAL),
        field('width', 3, :TYPE_UINT32), field('height', 4, :TYPE_UINT32),
        field('left', 5, :TYPE_SINT32), field('top', 6, :TYPE_SINT32), field('advance', 7, :TYPE_UINT32)
      ]),
      Google::Protobuf::DescriptorProto.new(name: 'fontstack', field: [
        field('name', 1, :TYPE_STRING), field('range', 2, :TYPE_STRING),
        field('glyphs', 3, :TYPE_MESSAGE, :LABEL_REPEATED, '.llmr.glyphs.glyph')
      ]),
      Google::Protobuf::DescriptorProto.new(name: 'glyphs', field: [
        field('stacks', 1, :TYPE_MESSAGE, :LABEL_REPEATED, '.llmr.glyphs.fontstack')
      ])
    ]
  ).to_proto)
  Glyph = pool.lookup('llmr.glyphs.glyph').msgclass
  Fontstack = pool.lookup('llmr.glyphs.fontstack').msgclass
  Message = pool.lookup('llmr.glyphs.glyphs').msgclass
  # reason: required schema fields share the same Protobuf presence API.
  REQUIRED_METRICS = %i[id width height left top advance].freeze

  def self.validate!(bytes)
    message = Message.decode(bytes)
    raise InvalidData, 'Glyph PBF has no fontstacks' if message.stacks.empty?

    message.stacks.each do |stack|
      raise InvalidData, 'Glyph PBF is missing fontstack name or range' unless stack.has_name? && stack.has_range?

      stack.glyphs.each do |glyph|
        unless REQUIRED_METRICS.all? { |name| glyph.public_send("has_#{name}?") }
          raise InvalidData, 'Glyph PBF is missing required metrics'
        end
        if glyph.has_bitmap? && glyph.bitmap.bytesize != (glyph.width + 6) * (glyph.height + 6)
          raise InvalidData, 'Glyph bitmap size does not match its dimensions'
        end
      end
    end
    true
  rescue Google::Protobuf::ParseError
    raise InvalidData, 'Invalid glyph Protobuf data'
  end
end

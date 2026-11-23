# frozen_string_literal: true

require "psych"

def field(mapping, name)
  return unless mapping.is_a?(Psych::Nodes::Mapping) && [nil, "tag:yaml.org,2002:map"].include?(mapping.tag)

  pairs = mapping.children.each_slice(2)
  return if pairs.any? { |key, _| key.respond_to?(:value) && key.value == "<<" }

  matches = pairs.select { |key, _| key.is_a?(Psych::Nodes::Scalar) && key.value == name }
  matches.first.last if matches.length == 1
end

file, repository, tag = ARGV
begin
  documents = Psych.parse_stream(File.read(file)).children
  exit 1 unless documents.length == 1

  image = field(documents.first.root, "image")
  repo_value = field(image, "repository")
  tag_value = field(image, "tag")
  exit 1 unless repo_value.is_a?(Psych::Nodes::Scalar) && repo_value.value == repository
  exit 1 unless tag_value.is_a?(Psych::Nodes::Scalar)
  exit 1 unless [repo_value, tag_value].all? { |value| [nil, "tag:yaml.org,2002:str"].include?(value.tag) }
  exit 1 if tag && tag_value.value != tag
rescue Psych::Exception, IOError, SystemCallError
  exit 1
end

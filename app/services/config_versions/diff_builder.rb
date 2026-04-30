module ConfigVersions
  class DiffBuilder
    Line = Struct.new(:kind, :text, keyword_init: true)

    def initialize(before_snapshot:, after_snapshot:, before_label:, after_label:)
      @before_snapshot = normalize_snapshot(before_snapshot)
      @after_snapshot = normalize_snapshot(after_snapshot)
      @before_label = before_label
      @after_label = after_label
    end

    def lines
      @lines ||= begin
        before_lines = JSON.pretty_generate(before_snapshot).lines(chomp: true)
        after_lines = JSON.pretty_generate(after_snapshot).lines(chomp: true)

        [
          Line.new(kind: :meta, text: "--- #{before_label}"),
          Line.new(kind: :meta, text: "+++ #{after_label}"),
          *diff_lines(before_lines, after_lines)
        ]
      end
    end

    def changed?
      lines.any? { |line| %i[added removed].include?(line.kind) }
    end

    private

    attr_reader :before_snapshot, :after_snapshot, :before_label, :after_label

    def normalize_snapshot(snapshot)
      return {} unless snapshot.is_a?(Hash)

      snapshot.deep_stringify_keys
    end

    def diff_lines(before_lines, after_lines)
      lcs = Array.new(before_lines.length + 1) { Array.new(after_lines.length + 1, 0) }

      (before_lines.length - 1).downto(0) do |before_index|
        (after_lines.length - 1).downto(0) do |after_index|
          lcs[before_index][after_index] =
            if before_lines[before_index] == after_lines[after_index]
              lcs[before_index + 1][after_index + 1] + 1
            else
              [ lcs[before_index + 1][after_index], lcs[before_index][after_index + 1] ].max
            end
        end
      end

      build_output_lines(before_lines, after_lines, lcs)
    end

    def build_output_lines(before_lines, after_lines, lcs)
      output = []
      before_index = 0
      after_index = 0

      while before_index < before_lines.length && after_index < after_lines.length
        if before_lines[before_index] == after_lines[after_index]
          output << Line.new(kind: :context, text: "  #{before_lines[before_index]}")
          before_index += 1
          after_index += 1
        elsif lcs[before_index + 1][after_index] >= lcs[before_index][after_index + 1]
          output << Line.new(kind: :removed, text: "- #{before_lines[before_index]}")
          before_index += 1
        else
          output << Line.new(kind: :added, text: "+ #{after_lines[after_index]}")
          after_index += 1
        end
      end

      while before_index < before_lines.length
        output << Line.new(kind: :removed, text: "- #{before_lines[before_index]}")
        before_index += 1
      end

      while after_index < after_lines.length
        output << Line.new(kind: :added, text: "+ #{after_lines[after_index]}")
        after_index += 1
      end

      output
    end
  end
end

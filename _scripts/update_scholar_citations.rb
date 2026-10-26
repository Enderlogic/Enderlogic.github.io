require "json"
require "nokogiri"
require "open-uri"
require "yaml"
require "time"
require "fileutils"

# Fetch one profile table, rather than requesting every paper separately.
module ScholarCitationUpdater
  def self.parse(html, scholar_id)
    doc = Nokogiri::HTML(html)
    rows = doc.css("#gsc_a_b tr.gsc_a_tr")
    raise "Scholar publication table is missing or empty" if rows.empty?

    rows.each_with_object({}) do |row, counts|
      link = row.at_css("a.gsc_a_at")
      cell = row.at_css("td.gsc_a_c a.gsc_a_ac")
      raise "Unexpected Scholar publication row" unless link && cell

      query = URI.decode_www_form(URI.parse(link["href"]).query.to_s).to_h
      owner, article_id = query.fetch("citation_for_view").split(":", 2)
      raise "Unexpected Scholar profile or paper identifier" unless owner == scholar_id && !article_id.to_s.empty?

      # Scholar uses an empty citation cell for an uncited paper and may append *.
      value = cell.text.strip.delete(",*")
      raise "Invalid citation count" unless value.empty? || value.match?(/\A\d+\z/)
      counts[article_id] = value.empty? ? 0 : value.to_i
    end
  end

  def self.update(root:, html: nil, now: Time.now.utc)
    scholar_id = YAML.load_file(File.join(root, "_data/socials.yml")).fetch("scholar_userid")
    data_path = File.join(root, "_data/google_scholar_citations.json")
    cache_path = File.join(root, ".cache/google-scholar/citations.json")
    snapshots = [data_path, cache_path].map do |path|
      next unless File.exist?(path)
      data = JSON.parse(File.read(path))
      Time.iso8601(data.fetch("updated_at"))
      data if data["scholar_id"] == scholar_id && data["citations"].is_a?(Hash)
    rescue JSON::ParserError, ArgumentError, KeyError
      nil
    end
    previous = snapshots.compact.max_by { |data| Time.iso8601(data.fetch("updated_at")) }
    # Restore newer successful counts from the CI cache before any network request.
    if previous
      File.write(data_path, JSON.pretty_generate(previous) + "\n")
      age = now - Time.iso8601(previous.fetch("updated_at"))
      if age >= 0 && age < 86_400
        puts "Google Scholar: using saved counts (less than one day old)."
        return previous
      end
    end

    unless html
      attempt_path = File.join(File.dirname(cache_path), "last_attempt.txt")
      if File.exist?(attempt_path)
        attempt_age = now - Time.iso8601(File.read(attempt_path).strip)
        if attempt_age >= 0 && attempt_age < 86_400
          puts "Google Scholar: already attempted a refresh today; keeping saved counts."
          return previous
        end
      end
      FileUtils.mkdir_p(File.dirname(cache_path))
      File.write(attempt_path, now.iso8601)
      query = URI.encode_www_form(user: scholar_id, hl: "en", pagesize: 100, sortby: "pubdate")
      html = URI.open("https://scholar.google.com/citations?#{query}",
                      "User-Agent" => "Mozilla/5.0", open_timeout: 10, read_timeout: 20, &:read)
    end
    counts = parse(html, scholar_id)
    # Keep older papers if they are not present in the first 100 profile results.
    data = { "scholar_id" => scholar_id, "updated_at" => now.iso8601,
             "citations" => (previous ? previous["citations"] : {}).merge(counts) }
    output = JSON.pretty_generate(data) + "\n"
    FileUtils.mkdir_p(File.dirname(cache_path))
    File.write(data_path, output)
    File.write(cache_path, output)
    puts "Google Scholar: saved citation counts for #{counts.size} papers."
    data
  rescue StandardError => e
    warn "Google Scholar refresh failed; keeping saved counts: #{e.class}: #{e.message}"
    previous
  end
end

if $PROGRAM_NAME == __FILE__
  ScholarCitationUpdater.update(root: File.expand_path("..", __dir__))
end

require "minitest/autorun"
require "tmpdir"
require "logger"
require "liquid"
require_relative "../update_scholar_citations"
require_relative "../../_plugins/google-scholar-citations"

class ScholarCitationsTest < Minitest::Test
  PROFILE = "GMeLKiQAAAAJ"

  def row(id, count)
    %(<tr class="gsc_a_tr"><td><a class="gsc_a_at" href="/citations?citation_for_view=#{PROFILE}:#{id}">Paper</a></td><td class="gsc_a_c"><a class="gsc_a_ac">#{count}</a></td></tr>)
  end

  def with_site
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "_data"))
      File.write(File.join(root, "_data/socials.yml"), "scholar_userid: #{PROFILE}\n")
      yield root
    end
  end

  def snapshot(count, time)
    { "scholar_id" => PROFILE, "updated_at" => time.iso8601, "citations" => { "paper" => count } }
  end

  def test_profile_table_counts_and_zero
    html = %(<table><tbody id="gsc_a_b">#{row('paper', '1,234*')}#{row('uncited', '')}</tbody></table>)
    assert_equal({ "paper" => 1234, "uncited" => 0 }, ScholarCitationUpdater.parse(html, PROFILE))
    assert_raises(RuntimeError) { ScholarCitationUpdater.parse("<html>unusual traffic</html>", PROFILE) }
    assert_raises(RuntimeError) { ScholarCitationUpdater.parse(%(<table id="gsc_a_b">#{row('paper', 'unavailable')}</table>), PROFILE) }
  end

  def test_blocked_response_keeps_last_success_and_throttles_retry
    with_site do |root|
      now = Time.utc(2026, 10, 26)
      path = File.join(root, "_data/google_scholar_citations.json")
      old = snapshot(42, now - 172800)
      File.write(path, JSON.generate(old))
      calls = 0
      URI.stub(:open, lambda { |*args| calls += 1; raise IOError, "403 Forbidden" }) do
        assert_equal old, ScholarCitationUpdater.update(root: root, now: now)
        assert_equal old, ScholarCitationUpdater.update(root: root, now: now + 60)
      end
      assert_equal 1, calls
      assert_equal old, JSON.parse(File.read(path))
    end
  end

  def test_newer_ci_snapshot_restored_without_fetch
    with_site do |root|
      now = Time.utc(2026, 10, 26)
      path = File.join(root, "_data/google_scholar_citations.json")
      File.write(path, JSON.generate(snapshot(12, now - 172800)))
      cache = File.join(root, ".cache/google-scholar/citations.json")
      FileUtils.mkdir_p(File.dirname(cache))
      fresh = snapshot(20, now - 3600)
      File.write(cache, JSON.generate(fresh))
      URI.stub(:open, lambda { |*args| flunk "Fresh cache must not fetch" }) do
        assert_equal fresh, ScholarCitationUpdater.update(root: root, now: now)
      end
      assert_equal fresh, JSON.parse(File.read(path))
    end
  end

  def test_success_merges_missing_papers_and_persists
    with_site do |root|
      now = Time.utc(2026, 10, 26)
      path = File.join(root, "_data/google_scholar_citations.json")
      File.write(path, JSON.generate(snapshot(42, now - 172800)))
      html = %(<table id="gsc_a_b">#{row('new', '10')}</table>)
      data = ScholarCitationUpdater.update(root: root, html: html, now: now)
      assert_equal({ "paper" => 42, "new" => 10 }, data["citations"])
      assert_equal data, JSON.parse(File.read(File.join(root, ".cache/google-scholar/citations.json")))
    end
  end

  def test_liquid_badges_use_saved_data
    template = Liquid::Template.parse("{% google_scholar_citations profile article %}")
    ctx = { "profile" => PROFILE, "article" => "paper", "site" => { "data" => { "google_scholar_citations" => snapshot(123, Time.now.utc) } } }
    assert_equal "123", template.render!(ctx)
    ctx["site"]["data"]["google_scholar_citations"]["citations"]["paper"] = 0
    assert_equal "0", template.render!(ctx)
    ctx["article"] = "missing"
    assert_equal "N/A", template.render!(ctx)
  end
end

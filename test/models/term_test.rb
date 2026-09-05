require "test_helper"

class TermTest < ActiveSupport::TestCase
  def setup
    Mongoid.purge!
    @school = School.create!(
      schoolName: "Grace Academy",
      schoolEmail: "grace@academy.org",
      user_email: "admin@grace.org"
    )
  end

  test "creating 4 non-overlapping terms succeeds" do
    t1 = Term.create!(school_id: @school.id.to_s, academic_year: 2026, term_number: 1, start_date: "2026-01-15", end_date: "2026-03-25")
    t2 = Term.create!(school_id: @school.id.to_s, academic_year: 2026, term_number: 2, start_date: "2026-04-05", end_date: "2026-06-20")
    t3 = Term.create!(school_id: @school.id.to_s, academic_year: 2026, term_number: 3, start_date: "2026-07-15", end_date: "2026-09-20")
    t4 = Term.create!(school_id: @school.id.to_s, academic_year: 2026, term_number: 4, start_date: "2026-10-01", end_date: "2026-12-10")

    assert_equal 4, Term.by_school(@school.id.to_s).count
    assert_equal "Term 1", t1.name
  end

  test "rejects overlapping date ranges in same school and academic year" do
    Term.create!(school_id: @school.id.to_s, academic_year: 2026, term_number: 1, start_date: "2026-01-15", end_date: "2026-03-25")

    overlapping = Term.new(school_id: @school.id.to_s, academic_year: 2026, term_number: 2, start_date: "2026-03-20", end_date: "2026-06-15")
    refute overlapping.valid?
    assert overlapping.errors[:base].any? { |e| e.include?("overlaps with existing Term 1") }
  end

  test "rejects duplicate term_number in same school and academic year" do
    Term.create!(school_id: @school.id.to_s, academic_year: 2026, term_number: 1, start_date: "2026-01-15", end_date: "2026-03-25")

    duplicate = Term.new(school_id: @school.id.to_s, academic_year: 2026, term_number: 1, start_date: "2026-04-01", end_date: "2026-06-15")
    refute duplicate.valid?
    assert duplicate.errors[:term_number].any? { |e| e.include?("already exists") }
  end

  test "Term.current_for_school identifies active term on Date.current" do
    today = Date.current
    active_term = Term.create!(
      school_id: @school.id.to_s,
      academic_year: today.year,
      term_number: 1,
      start_date: today - 10.days,
      end_date: today + 10.days
    )

    assert_equal active_term, Term.current_for_school(@school.id.to_s)
    assert active_term.is_current?
  end
end

require "test_helper"

class GroupConversationServiceTest < ActiveSupport::TestCase
  def setup
    Mongoid.purge!
    @school = School.create!(
      schoolName: "Apex Group High",
      schoolEmail: "apex@group.org",
      user_email: "admin@group.org"
    )
    @grade = Grade.create!(name: "Grade 10", level: 10, school: @school)
    @school_class = SchoolClass.create!(name: "10A", grade: @grade)

    @parent1 = User.create!(
      name: "Parent One",
      email: "p1@group.org",
      auth0_id: "auth0|p1",
      roles: ["parent"]
    )
    @parent2 = User.create!(
      name: "Parent Two",
      email: "p2@group.org",
      auth0_id: "auth0|p2",
      roles: ["parent"]
    )

    @teacher = User.create!(
      name: "Teacher One",
      email: "t1@group.org",
      auth0_id: "auth0|t1",
      roles: ["teacher"],
      school_ids: [@school.id.to_s]
    )

    @learner1 = Learner.create!(
      first_name: "Child",
      last_name: "One",
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      school_class_id: @school_class.id.to_s,
      parent_ids: [@parent1.id]
    )

    @learner2 = Learner.create!(
      first_name: "Child",
      last_name: "Two",
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      school_class_id: @school_class.id.to_s,
      parent_ids: [@parent2.id]
    )

    @unlinked_learner = Learner.create!(
      first_name: "Child",
      last_name: "Unlinked",
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      school_class_id: @school_class.id.to_s,
      parent_ids: []
    )

    @school_class.update(learner_ids: [@learner1.id.to_s, @learner2.id.to_s, @unlinked_learner.id.to_s])
  end

  test "resolve_participants for class scope resolves linked parents and excludes unlinked ones" do
    participants = GroupConversationService.resolve_participants(@school.id.to_s, "class", @school_class.id.to_s)
    assert_includes participants, @parent1.id.to_s
    assert_includes participants, @parent2.id.to_s
    assert_equal 2, participants.size
  end

  test "resolve_participants for grade scope resolves linked parents" do
    participants = GroupConversationService.resolve_participants(@school.id.to_s, "grade", @grade.id.to_s)
    assert_includes participants, @parent1.id.to_s
    assert_includes participants, @parent2.id.to_s
  end

  test "resolve_participants for teachers scope resolves teachers" do
    participants = GroupConversationService.resolve_participants(@school.id.to_s, "teachers", nil)
    assert_includes participants, @teacher.id.to_s
  end
end

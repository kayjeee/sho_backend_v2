class ClassManagementService
  def initialize(grade, school_class = nil)
    @grade = grade
    @school_class = school_class
  end

  def transfer_learners_batch(learner_ids, target_class_id)
    target_class = @grade.school_classes.find(target_class_id)

    return { success: false, error: "Target class is full" } if target_class.full?

    learner_ids.each do |learner_id|
      move_individual_learner(learner_id, target_class)
    end

    { success: true, message: "#{learner_ids.count} learners transferred successfully" }
  rescue => e
    { success: false, error: e.message }
  end

  def reassign_all_teachers(new_teacher_assignments)
    # Using Mongoid's equivalent of transactions if available, or simple iterative updates
    # For Phase 1, we'll perform these as a batch update on the document
    begin
      new_teacher_assignments.each do |assignment|
        case assignment[:role]
        when 'class_teacher'
          @school_class.assign_class_teacher(assignment[:teacher_id])
        when 'subject_teacher'
          @school_class.assign_subject_teacher(assignment[:subject_id], assignment[:teacher_id])
        end
      end
      { success: true, message: "Teachers reassigned successfully" }
    rescue => e
      { success: false, error: e.message }
    end
  end

  def bulk_create_classes(class_names, default_capacity = 40)
    created = []
    errors = []

    class_names.each do |class_name|
      school_class = @grade.school_classes.new(name: class_name, capacity: default_capacity)
      if school_class.save
        created << school_class
      else
        errors << { class_name: class_name, errors: school_class.errors.full_messages }
      end
    end

    { success: errors.empty?, created: created, errors: errors }
  end

  private

  def move_individual_learner(learner_id, target_class)
    bson_id = BSON::ObjectId.from_string(learner_id.to_s)

    # Remove from current class
    @school_class.pull(learner_ids: bson_id)

    # Add to target class
    target_class.add_to_set(learner_ids: bson_id)

    # Update learner record
    # Phase 1 assumes Learner model has grade_id and school_class_id
    learner = Learner.find(learner_id)
    learner.update(grade_id: @grade.id, school_class_id: target_class.id)
  end
end

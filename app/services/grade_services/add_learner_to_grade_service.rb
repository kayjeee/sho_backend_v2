# app/services/grade_services/add_learner_to_grade_service.rb
module GradeServices
  class AddLearnerToGradeService
    def initialize(grade:, current_user:, learner_id:)
      @grade = grade
      @current_user = current_user
      @learner_id = learner_id
    end

    def call
      learner = Learner.find(@learner_id)

      if @grade.learners.include?(learner)
        return ServiceResult.new(success: false, errors: [ "Learner already in this grade" ])
      end

      if @grade.current_enrollment_count >= @grade.capacity
        return ServiceResult.new(success: false, errors: [ "Grade has reached maximum capacity" ])
      end

      @grade.learners << learner

      if @grade.save
        log_addition(learner)
        ServiceResult.new(success: true, learner: learner)
      else
        ServiceResult.new(success: false, errors: @grade.errors.full_messages)
      end
    rescue Mongoid::Errors::DocumentNotFound
      ServiceResult.new(success: false, errors: [ "Learner not found" ])
    end

    private

    def log_addition(learner)
      AuditLog.create!(
        user: @current_user,
        action: "add_learner_to_grade",
        record: @grade,
        associated_record: learner,
        details: "Added learner #{learner.full_name} to grade #{@grade.name}",
        timestamp: Time.current
      )
    end
  end
end

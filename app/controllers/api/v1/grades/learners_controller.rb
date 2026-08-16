module Api
  module V1
    module Grades
      class LearnersController < Api::V1::BaseController
        def index
          grade_id = params[:grade_id]
          school_id = params[:school_id] || params[:schoolId]

          if grade_id.blank?
            return render json: { success: false, error: "Grade identifier is required." }, status: :bad_request
          end

          begin
            @grade = Grade.find(grade_id)
          rescue Mongoid::Errors::DocumentNotFound, Mongoid::Errors::InvalidFind
            return render json: { success: false, error: "Grade not found." }, status: :not_found
          end

          # The production database collection strictly stores relation values as 'gradeId' (camelCase string or BSON::ObjectId)
          query = { "gradeId" => { "$in" => [@grade.id.to_s, @grade.id] } }

          # Query school_id as a string if provided
          if school_id.present?
            query["school_id"] = school_id.to_s
          end

          # Fetch using the Mongo Ruby driver and safely convert/instantiate back to Mongoid model instances
          raw_docs = Learner.collection.find(query)
          @learners = raw_docs.map { |doc| Learner.instantiate(doc) }

          render json: {
            success: true,
            total: @learners.size,
            learners: @learners.map { |learner|
              {
                id: learner.id.to_s,
                firstName: learner.try(:firstName) || learner.try(:first_name),
                lastName: learner.try(:lastName) || learner.try(:last_name),
                gender: learner.gender,
                accessionNumber: learner.accession_number,
                accession_number: learner.accession_number,
                gradeId: @grade.id.to_s,
                school_id: learner.school_id.to_s,
                parent_id: learner.try(:parent_id)&.to_s || nil,
                status: learner.try(:status) || "active",
                contact: {
                  phone: learner.try(:phone),
                  whatsapp: learner.try(:whatsapp),
                  tel_home: learner.try(:tel_home) || learner.try(:telHome) || learner.read_attribute(:telHome) || learner.read_attribute(:tel_home),
                  tel_emergency: learner.try(:tel_emergency) || learner.try(:telEmergency) || learner.read_attribute(:telEmergency) || learner.read_attribute(:tel_emergency),
                  telegram: learner.try(:telegram)
                }
              }
            }
          }, status: :ok
        end
      end
    end
  end
end

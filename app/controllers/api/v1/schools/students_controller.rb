# app/controllers/api/v1/schools/students_controller.rb
module Api::V1::Schools
    class StudentsController < ApplicationController
      before_action :set_school
      before_action :set_student, only: [ :show, :update, :destroy ]

      # GET /api/v1/schools/:school_id/students
      def index
        students = @school.students
        students = students.where(grade: params[:grade]) if params[:grade]
        students = students.where(status: params[:status]) if params[:status]

        render json: students.map(&:full_profile), status: :ok
      end

      # GET /api/v1/schools/:school_id/students/:id
      def show
        render json: @student.full_profile.merge(
          account_details: {
            balance: @student.account.balance,
            status: @student.account.status
          }
        ), status: :ok
      end

      # POST /api/v1/schools/:school_id/students
      def create
        student = @school.students.new(student_params)
        if student.save
          render json: student.full_profile, status: :created
        else
          render json: { errors: student.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/schools/:school_id/students/:id
      def update
        if @student.update(student_params)
          render json: @student.full_profile, status: :ok
        else
          render json: { errors: @student.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/schools/:school_id/students/:id
      def destroy
        @student.update(status: "inactive") # Soft delete
        head :no_content
      end

      private

      def set_school
        @school = School.find(params[:school_id])
      end

      def set_student
        @student = @school.students.find(params[:id])
      end

      def student_params
        params.require(:student).permit(
          :name, :grade, :avatar, :date_of_birth, :gender, :status,
          :primary_contact_name, :primary_contact_relationship,
          :primary_contact_email, :primary_contact_phone,
          :secondary_contact_name, :secondary_contact_phone,
          :enrollment_date, :homeroom, :medical_notes,
          special_needs: []
        )
      end
    end
end

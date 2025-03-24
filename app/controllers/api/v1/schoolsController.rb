module Api
  module V1
    class SchoolsController < ApplicationController
      # GET /api/v1/schools/search
def index
  schools = School.all
  render json: { success: true, schools: schools }, status: 200
end 

      def search
        query = params[:query]

        if query.present?
          school_exists = School.where(:schoolName => /^#{Regexp.escape(query)}$/i).exists?

          if school_exists
            render json: { success: true, isAvailable: false, message: "School name is already taken." }, status: 200
          else
            render json: { success: true, isAvailable: true, message: "School name is available!" }, status: 200
          end
        else
          render json: { success: false, message: "Query parameter is missing." }, status: 400
        end
      rescue => e
        render json: { success: false, message: "An error occurred: #{e.message}" }, status: 500
      end

      # POST /api/v1/schools
     def create
        school = School.new(school_params)

        # Assign the user_email and user_id to the school object
        school.user_email = params[:user_email]
        school.user_id = params[:user_id]
        school.school_created_by = params[:school_created_by]


        # Populate null fields with default values from the payload
        populate_null_fields(school)

        if school.save
          render json: { success: true, school: school, message: "School created successfully." }, status: 201
        else
          render json: { success: false, errors: school.errors.full_messages }, status: 422
        end
      end


      def show
        school = School.find(params[:id])
        if school
          render json: { success: true, school: school }, status: 200
        else
          render json: { success: false, message: "School not found." }, status: 404
        end
      end

      

      # DELETE /api/v1/schools/:id]]
    # when testing with postman isert the id into the body
    def destroy
      begin
        # Sanitize the ID parameter by stripping whitespace
        sanitized_id = params[:id].strip
        school = School.find(BSON::ObjectId.from_string(sanitized_id))
        school.destroy
        render json: { success: true, message: "School deleted successfully." }, status: :ok
      rescue BSON::ObjectId::Invalid => e
        render json: { success: false, message: "Invalid ObjectId: #{e.message}" }, status: :unprocessable_entity
      rescue Mongoid::Errors::DocumentNotFound
        render json: { success: false, message: "School not found." }, status: :not_found
      rescue StandardError => e
        render json: { success: false, message: "An error occurred: #{e.message}" }, status: :internal_server_error
      end
    end
    

      def update
        sanitized_id = params[:id].strip
        school = School.find(BSON::ObjectId.from_string(sanitized_id))
      
        if school
          school.assign_attributes(school_params)
          populate_null_fields(school)
      
          if school.save
            render json: { success: true, school: school, message: "School updated successfully." }, status: 200
          else
            render json: { success: false, errors: school.errors.full_messages }, status: 422
          end
        else
          render json: { success: false, message: "School not found." }, status: 404
        end
      end
      


      private

      def school_params
        mapped_params = params[:school].dup
        mapped_params[:schoolEmail] = mapped_params.delete(:schoolemail) if mapped_params[:schoolemail]
        mapped_params.permit(
          :schoolName, :schoolEmail, :country, :city, :province,
          :latitude, :longitude, :facebook, :linkedin, :tiktok,
          :theme, :website, :logo, schoolAddress: [:line1, :line2, :country, :province, :city, :postalCode]
        )
      end

      def populate_null_fields(school)
        payload = params[:school] || {}
        school.user_id ||= payload[:user_id]
        school.user_email ||= payload[:user_email]
        school.country ||= payload[:country]
        school.city ||= payload[:city]
        school.province ||= payload[:province]
        school.latitude ||= payload[:latitude]
        school.longitude ||= payload[:longitude]
        school.facebook ||= payload[:facebook]
        school.linkedin ||= payload[:linkedin]
        school.tiktok ||= payload[:tiktok]
        school.theme ||= payload[:theme]
        school.website ||= payload[:website]
        school.logo ||= payload[:logo]
      end
     
      
      def populate_null_fields(school)
        payload = params[:school] || {}
      
        school.country ||= payload[:country]
        school.city ||= payload[:city]
        school.province ||= payload[:province]
        school.latitude ||= payload[:latitude]
        school.longitude ||= payload[:longitude]
        school.facebook ||= payload[:facebook]
        school.linkedin ||= payload[:linkedin]
        school.tiktok ||= payload[:tiktok]
        school.theme ||= payload[:theme]
        school.website ||= payload[:website]
        school.logo ||= payload[:logo]
      end
      
      def school_params
        params.require(:school).permit(
          :schoolName, :schoolEmail, :country, :city, :province, 
          :latitude, :longitude, :facebook, :linkedin, :tiktok, 
          :theme, :website, :logo, 
          schoolAddress: [:line1, :line2, :country, :province, :city, :postalCode]
        )
      end

      def school_params
        mapped_params = params[:school].dup
        mapped_params[:schoolEmail] = mapped_params.delete(:schoolemail) if mapped_params[:schoolemail]
        mapped_params.permit(:schoolName, :schoolEmail, :country, :city, :schoolAddress, :theme, :website, :latitude, :longitude, :facebook, :linkedin, :tiktok)
      end
      
    end
  end
end

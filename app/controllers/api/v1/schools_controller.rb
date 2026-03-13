module Api
  module V1
    class SchoolsController < ApplicationController
      before_action :set_school, only: [:show, :update, :destroy, :admins, :teachers, :parents]

      # =========================
      # GET /api/v1/schools
      # =========================
      def index
        page = (params[:page] || 1).to_i
        limit = (params[:limit] || 20).to_i
        search_query = params[:search]

        schools = School.all

        if search_query.present?
          schools = schools.where(schoolName: /#{Regexp.escape(search_query)}/i)
        end

        total_count = schools.count
        schools_paginated = schools.skip((page - 1) * limit).limit(limit)

        render_success(data: {
          schools: schools_paginated.map(&:to_api_hash),
          totalCount: total_count,
          page: page,
          limit: limit
        })
      rescue => e
        handle_exception(e, "Failed to fetch schools")
      end

      # =========================
      # GET /api/v1/schools/:school_id/parents/:parent_id
      # =========================
      def show_parent
        user_role = UserSchoolRole.find_by(
          school_id: params[:id],
          user_id: params[:parent_id],
          role: 'Parent'
        )

        unless user_role
          return render_error("Parent not found in this school", [], status: :not_found)
        end

        parent = User.find(params[:parent_id])
        render_success(data: {
          parent: {
            id: parent.id.to_s,
            name: parent.name,
            email: parent.email,
            auth0_id: parent.auth0_id,
            role: 'Parent'
          }
        })
      rescue Mongoid::Errors::DocumentNotFound
        render_error("Parent not found", [], status: :not_found)
      rescue => e
        handle_exception(e, "Failed to fetch parent")
      end

      # =========================
      # GET /api/v1/schools/:id/admins
      # =========================
      def admins
        users = fetch_users_by_role('Admin')
        render_success(data: users)
      rescue => e
        handle_exception(e, "Failed to fetch admins")
      end

      # =========================
      # GET /api/v1/schools/:id/teachers
      # =========================
      def teachers
        users = fetch_users_by_role('Teacher')
        render_success(data: users)
      rescue => e
        handle_exception(e, "Failed to fetch teachers")
      end

      # =========================
      # GET /api/v1/schools/:id/parents
      # =========================
      def parents
        users = fetch_users_by_role('Parent')
        render_success(data: users)
      rescue => e
        handle_exception(e, "Failed to fetch parents")
      end

      # =========================
      # GET /api/v1/schools/search?query=Name
      # =========================
      def search
        query = params[:query]
        return render_error("Query parameter is missing.", [], status: :bad_request) if query.blank?

        school_exists = School.where(schoolName: /^#{Regexp.escape(query)}$/i).exists?
        render_success(data: {
          isAvailable: !school_exists,
          message: school_exists ? "School name is taken" : "School name available"
        })
      rescue => e
        handle_exception(e, "School search failed")
      end

      # =========================
      # POST /api/v1/schools
      # =========================
      def create
        permitted = school_params
        theme_data = permitted.delete(:theme)
        admin_users_data = permitted.delete(:adminUsers)
        invites_data = permitted.delete(:invites)
        
        @school = School.new(permitted)
        @school.cash_account ||= 0.0
        @school.payment_history ||= []
        @school.status ||= "active"

        if theme_data.present?
          @school.theme = convert_theme_to_string(theme_data)
        else
          @school.theme = ""
        end

        if admin_users_data.present? && admin_users_data.is_a?(Array)
          @school.adminUsers = admin_users_data.map do |admin|
            {
              id: admin[:id] || admin["id"] || Time.now.to_i.to_s,
              name: admin[:name] || admin["name"],
              email: admin[:email] || admin["email"],
              role: admin[:role] || admin["role"] || "Administrator",
              addedAt: admin[:addedAt] || admin["addedAt"] || Time.current
            }
          end.compact
        else
          @school.adminUsers = []
        end

        if invites_data.present? && invites_data.is_a?(Array)
          @school.invites = invites_data.map do |invite|
            {
              id: invite[:id] || invite["id"] || Time.now.to_i.to_s,
              email: invite[:email] || invite["email"],
              role: invite[:role] || invite["role"] || "Staff",
              status: invite[:status] || invite["status"] || "pending",
              invitedAt: invite[:invitedAt] || invite["invitedAt"] || Time.current
            }
          end.compact
        else
          @school.invites = []
        end

        if @school.save
          associate_user_with_school
          render_success(message: "School created successfully", data: { school: @school.to_api_hash }, status: :created)
        else
          render_error("School validation failed", @school.errors.full_messages)
        end
      rescue Mongo::Error::OperationFailure => e
        handle_exception(e, "Database operation failed")
      rescue ActionController::ParameterMissing => e
        render_error("Missing required parameter", [e.message], status: :bad_request)
      rescue => e
        handle_exception(e, "School creation failed")
      end

      # =========================
      # GET /api/v1/schools/:id
      # =========================
      def show
        render_success(data: { school: @school.to_api_hash })
      end

      # =========================
      # PATCH/PUT /api/v1/schools/:id
      # =========================
      def update
        permitted = school_params
        theme_data = permitted.delete(:theme)
        admin_users_data = permitted.delete(:adminUsers)
        invites_data = permitted.delete(:invites)

        if theme_data.present?
          @school.theme = convert_theme_to_string(theme_data)
        end

        if admin_users_data.present? && admin_users_data.is_a?(Array)
          @school.adminUsers = admin_users_data.map do |admin|
            {
              id: admin[:id] || admin["id"] || Time.now.to_i.to_s,
              name: admin[:name] || admin["name"],
              email: admin[:email] || admin["email"],
              role: admin[:role] || admin["role"] || "Administrator",
              addedAt: admin[:addedAt] || admin["addedAt"] || Time.current
            }
          end.compact
        end

        if invites_data.present? && invites_data.is_a?(Array)
          @school.invites = invites_data.map do |invite|
            {
              id: invite[:id] || invite["id"] || Time.now.to_i.to_s,
              email: invite[:email] || invite["email"],
              role: invite[:role] || invite["role"] || "Staff",
              status: invite[:status] || invite["status"] || "pending",
              invitedAt: invite[:invitedAt] || invite["invitedAt"] || Time.current
            }
          end.compact
        end

        if @school.update(permitted)
          render_success(message: "School updated successfully", data: { school: @school.to_api_hash })
        else
          render_error("School update failed", @school.errors.full_messages)
        end
      rescue Mongo::Error::OperationFailure => e
        handle_exception(e, "Database operation failed")
      rescue => e
        handle_exception(e, "School update failed")
      end

      # =========================
      # DELETE /api/v1/schools/:id
      # =========================
      def destroy
        @school.destroy
        render_success(message: "School deleted successfully")
      rescue => e
        handle_exception(e, "Failed to delete school")
      end

      private

      def set_school
        # Support finding by ID, Slug, or Name fallback
        id_param = params[:id] || params[:school_id] || params[:school_slug]

        @school = School.find(id_param) rescue nil
        @school ||= School.find_by(slug: id_param)

        # Name-based fallback (replace hyphens with spaces and regex match)
        if @school.nil? && id_param.present?
          search_name = id_param.to_s.gsub('-', ' ')
          @school = School.where(schoolName: /#{Regexp.escape(search_name)}/i).first
        end

        unless @school
          render_error("School not found", [], status: :not_found)
        end
      end

      def fetch_users_by_role(role)
        user_roles = UserSchoolRole.where(school_id: @school.id, role: role)
        User.in(id: user_roles.pluck(:user_id)).map do |user|
          {
            id: user.id.to_s,
            name: user.name,
            email: user.email,
            auth0_id: user.auth0_id,
            role: role
          }
        end
      end

      def convert_theme_to_string(theme_data)
        return "" if theme_data.blank?
        theme_hash = if theme_data.is_a?(Hash)
          {
            "mode" => theme_data[:mode] || theme_data["mode"] || "",
            "value" => theme_data[:value] || theme_data["value"] || ""
          }
        elsif theme_data.is_a?(String)
          { "mode" => theme_data, "value" => "" }
        else
          {}
        end
        theme_hash.inspect
      rescue => e
        Rails.logger.warn "Failed to convert theme: #{e.message}"
        ""
      end

      def associate_user_with_school
        user_id = @school.user_id
        return unless user_id.present?

        user = User.find_by(auth0_id: user_id)
        if user
          user.add_school(@school.id)
        end
      end

      def school_params
        params.require(:school).permit(
          :schoolName, :schoolEmail, :country, :city, :province,
          :latitude, :longitude, :facebook, :linkedin, :tiktok,
          :website, :logo, :status, :line1, :line2, :postalCode,
          :user_id, :user_email, :school_created_by,
          theme: [:mode, :value],
          adminUsers: [:id, :name, :email, :role, :addedAt],
          invites: [:id, :email, :role, :status, :invitedAt]
        )
      end
    end
  end
end

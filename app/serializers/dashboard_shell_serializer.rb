# frozen_string_literal: true

class DashboardShellSerializer
  def initialize(school, user)
    @school = school
    @user = user
    @admin_metadata = school.admin_user_for_email(user&.email)
  end

  def as_json
    {
      school_name: @school.schoolName,
      school_logo: @school.logo,
      current_user: current_user_payload,
      theme: @school.resolved_theme,
      school_meta: school_meta_payload
    }
  end

  private

  def current_user_payload
    {
      name: resolved_user_name,
      email: @user&.email,
      resolved_active_roles: @user&.resolved_active_roles_for_school(@school) || []
    }
  end

  def school_meta_payload
    {
      location: @school.dashboard_location,
      province: @school.province
    }
  end

  def resolved_user_name
    admin_name = @admin_metadata&.fetch('name', nil) || @admin_metadata&.fetch(:name, nil)
    admin_name.presence || @user&.display_name
  end
end

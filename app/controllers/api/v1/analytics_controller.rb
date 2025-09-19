class Api::V1::AnalyticsController < ApplicationController
  # before_action :set_school # Assumes school is set for scoping

  def invites
    # In a real app, you would scope this to a school
    # invites = Invite.where(school: @school)
    invites = Invite.all
    
    stats = {
      total_invites: invites.count,
      by_status: invites.group_by(&:status).transform_values(&:count),
      by_channel: invites.all.flat_map(&:channels).group_by(&:itself).transform_values(&:count)
    }
    
    render json: stats
  end

  def pr_codes
    # pr_codes = PrCode.where(school: @school)
    pr_codes = PrCode.all

    stats = {
      total_pr_codes: pr_codes.count,
      by_status: pr_codes.group_by(&:status).transform_values(&:count),
      by_recipient_type: pr_codes.group_by(&:recipient_type).transform_values(&:count)
    }

    render json: stats
  end

  def engagement
    # This is a placeholder for a more complex engagement tracking system.
    # A full implementation would likely involve tracking link clicks,
    # QR code scans, and conversion events.
    render json: { 
      message: "Engagement analytics endpoint is under development.",
      sample_metrics: [
        "Invite-to-Registration Conversion Rate",
        "Time-to-Conversion",
        "Channel Performance (e.g., WhatsApp vs. Email)"
      ]
    }
  end

  private

  # Mock set_school for demonstration
  def set_school
    @school = School.first
    render json: { error: 'School not found' }, status: :not_found unless @school
  end
end

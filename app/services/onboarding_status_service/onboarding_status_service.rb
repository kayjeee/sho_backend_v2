# app/controllers/api/v1/onboarding_statuses_controller.rb
def complete_step
  step_name = params[:step_name]
  step_metadata = params[:metadata] || {}

  if step_name.blank?
    return render json: { success: false, errors: ["Step name is required"], message: "Missing step name parameter" },
                  status: :bad_request
  end

  metadata_hash = step_metadata.respond_to?(:to_unsafe_hash) ? step_metadata.to_unsafe_hash : step_metadata.to_h

  validation_result = validate_step_metadata(step_name, metadata_hash)
  unless validation_result[:valid]
    return render json: { success: false, errors: validation_result[:errors], message: "Invalid step metadata" },
                  status: :bad_request
  end

  safe_metadata = {}
  safe_metadata["grades"]   = Array.wrap(metadata_hash["grades"]).compact if metadata_hash["grades"].present?
  safe_metadata["schoolId"] = metadata_hash["schoolId"] if metadata_hash["schoolId"].present?

  enriched_metadata = safe_metadata.merge(
    "request_id" => request.uuid,
    "user_agent" => request.user_agent,
    "ip_address" => request.remote_ip
  )

  begin
    current_status = @target_user.onboarding_status || {}
    new_status = current_status.merge(step_name.to_s => enriched_metadata)

    @target_user.set(onboarding_status: new_status)

    if step_name.to_s == "create_grades"
      GradeCreationService.create_from_metadata(@target_user, safe_metadata)
    end

    render json: {
      success: true,
      message: "Step '#{step_name}' completed",
      data: enriched_metadata,
      metadata: @request_context
    }
  rescue => e
    Rails.logger.error "🔥 Error completing step: #{e.message}\n#{e.backtrace.join("\n")}"
    render json: { success: false, message: "Unexpected error", errors: [e.message] }, status: :internal_server_error
  end
end

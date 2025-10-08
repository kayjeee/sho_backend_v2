# Events Controller
module Api::V1::
    class EventsController < ApplicationController
      before_action :set_school
      before_action :set_event, only: [:show, :update, :destroy, :publish, :registrations]
  
      # GET /api/v1/schools/:school_id/events
      def index
        events = @school.events
        events = events.where(event_type: params[:type]) if params[:type]
        events = events.where(is_published: true) unless current_user_admin?
        
        render json: events.upcoming, each_serializer: EventSerializer
      end
  
      # POST /api/v1/schools/:school_id/events
      def create
        @event = @school.events.new(event_params)
        @event.organizer = current_user.name if current_user
        
        if @event.save
          render json: @event, status: :created
        else
          render json: { errors: @event.errors.full_messages }, status: :unprocessable_entity
        end
      end
  
      # PATCH /api/v1/schools/:school_id/events/:id/publish
      def publish
        if @event.update(is_published: !@event.is_published?)
          render json: { message: "Event #{@event.is_published? ? 'published' : 'unpublished'}" }
        else
          render json: { errors: @event.errors.full_messages }, status: :unprocessable_entity
        end
      end
  
      private
      
      def set_school
        @school = School.find(params[:school_id])
      end
  
      def set_event
        @event = @school.events.find(params[:id])
      end
  
      def event_params
        params.require(:event).permit(
          :title, :description, :event_type, :start_time, :end_time,
          :location, :audience, :registration_required, :max_attendees,
          :featured_image, :contact_email, :contact_phone, :metadata
        )
      end
    end
  end

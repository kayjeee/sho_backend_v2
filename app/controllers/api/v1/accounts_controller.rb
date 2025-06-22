module Api
    module V1
      class AccountsController < ApplicationController
        def show_parent
          # Parameters now come from the URL path correctly
          school_id = params[:school_id]
          account_id = params[:account_id]
  
          # Validate presence
          if school_id.blank? || account_id.blank?
            return render json: {
              success: false,
              error: "Missing school_id or account_id"
            }, status: :bad_request
          end
  
          begin
            @account = Account.find_by(
              school_id: BSON::ObjectId(school_id),
              _id: BSON::ObjectId(account_id),
              account_type: 'parent' # Hardcoded since this is the parents endpoint
            )
  
            if @account
              render json: {
                success: true,
                account: format_account_response(@account)
              }, status: :ok
            else
              render json: {
                success: false,
                error: "Parent account not found"
              }, status: :not_found
            end
          rescue BSON::Error::InvalidObjectId
            render json: {
              success: false,
              error: "Invalid ID format"
            }, status: :bad_request
          end
        end
  
        private
  
        def format_account_response(account)
          {
            id: account.id.to_s,
            user_id: account.user_id.to_s,
            school_id: account.school_id.to_s,
            account_type: account.account_type,
            status: account.status,
            balance: account.balance.to_f,
            payment_history: account.payment_history
          }
        end
      end
    end
  end
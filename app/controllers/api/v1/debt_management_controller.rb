# app/controllers/api/v1/debt_management_controller.rb
module Api
  module V1
    class DebtManagementController < ApplicationController
      before_action :set_school
      before_action :set_account, only: [:show_account, :account_payments, :create_payment]

      # GET /api/v1/schools/:school_id/debt_summary
      def summary
        accounts = @school.accounts.with_balance
        
        render json: {
          total_debt: accounts.sum(:balance),
          total_accounts: accounts.count,
          average_debt: calculate_average_debt(accounts),
          overdue_accounts: accounts.overdue.count,
          due_this_week: accounts.due_this_week.count,
          last_updated: Time.current.iso8601
        }
      end

      # GET /api/v1/schools/:school_id/debtors
      def index
        accounts = @school.accounts.with_balance
        render json: accounts.map { |account| format_account(account) }
      end

      # GET /api/v1/schools/:school_id/accounts/:account_id
      def show_account
        render json: {
          account: format_account(@account),
          payment_history: @account.payment_history
        }
      end

      # GET /api/v1/schools/:school_id/accounts/:account_id/payments
      def account_payments
        render json: {
          payments: @account.payment_history,
          payment_stats: payment_stats(@account)
        }
      end

      # POST /api/v1/schools/:school_id/accounts/:account_id/payments
      def create_payment
        payment = @account.add_payment(
          payment_params[:amount].to_f,
          payment_params[:method],
          payment_params[:description]
        )

        if @account.errors.empty?
          render json: {
            payment: payment,
            new_balance: @account.balance,
            status: @account.status
          }, status: :created
        else
          render json: { errors: @account.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def set_school
        @school = School.find(params[:school_id] || params[:id])
      rescue Mongoid::Errors::DocumentNotFound
        render json: { error: "School not found" }, status: :not_found
      end

      def set_account
        @account = @school.accounts.find(params[:account_id])
      rescue Mongoid::Errors::DocumentNotFound
        render json: { error: "Account not found" }, status: :not_found
      end

      def payment_params
        params.require(:payment).permit(:amount, :method, :description)
      end

      def calculate_average_debt(accounts)
        count = accounts.count
        count.positive? ? accounts.sum(:balance) / count : 0
      end

      def format_account(account)
        {
          id: account.id.to_s,
          account_type: account.account_type,
          user: {
            id: account.user.id.to_s,
            name: account.user.name,
            email: account.user.email
          },
          balance: account.balance,
          due_date: account.due_date,
          status: account.status,
          days_overdue: account.days_overdue,
          last_payment: account.payment_history.first
        }
      end

      def payment_stats(account)
        payments = account.payment_history
        total_paid = payments.sum { |p| p['amount'].to_f }
        
        {
          count: payments.size,
          total_paid: total_paid,
          average_payment: payments.empty? ? 0 : total_paid / payments.size
        }
      end
    end
  end
end
class TransactionsController < ApplicationController
    before_action :set_transaction, only: [:show, :process_payment]
  
    # GET /transactions
    def index
      @transactions = Transaction.all
      render json: @transactions
    end
  
    # GET /transactions/:id
    def show
      render json: @transaction
    end
  
    # POST /transactions
    def create
      @transaction = Transaction.new(transaction_params)
  
      if @transaction.save
        render json: @transaction, status: :created
      else
        render json: @transaction.errors, status: :unprocessable_entity
      end
    end
  
    # POST /transactions/:id/process_payment
    def process_payment
      # Simulate payment processing (replace with actual payment gateway integration)
      payment_successful = true # Replace with actual payment gateway logic
  
      if payment_successful
        @transaction.update(status: 'completed')
        render json: { message: 'Payment processed successfully', transaction: @transaction }
      else
        @transaction.update(status: 'failed')
        render json: { error: 'Payment failed', transaction: @transaction }, status: :unprocessable_entity
      end
    end
  
    private
  
    def set_transaction
      @transaction = Transaction.find(params[:id])
    end
  
    def transaction_params
      params.require(:transaction).permit(:user_id, :school_id, :amount)
    end
  end 
class TransactionsController < ApplicationController
  before_action :set_transaction, only: [:show, :update, :destroy, :process_payment]
  before_action :set_school, only: [:index, :create]

  # GET /transactions
  # GET /api/v1/schools/:school_id/transactions
  def index
    transactions = if params[:school_id]
                     @school.transactions
                   else
                     Transaction.all
                   end

    # Filtering
    transactions = transactions.where(student_id: params[:student_id]) if params[:student_id]
    transactions = transactions.where(status: params[:status]) if params[:status]
    transactions = transactions.where(transaction_type: params[:type]) if params[:type]

    # Pagination and sorting
    transactions = transactions.order(created_at: :desc)
    
    render json: transactions, each_serializer: TransactionSerializer
  end

  # GET /transactions/:id
  def show
    render json: @transaction, serializer: TransactionDetailSerializer
  end

  # POST /transactions
  # POST /api/v1/schools/:school_id/transactions
  def create
    @transaction = if params[:school_id]
                     @school.transactions.new(transaction_params)
                   else
                     Transaction.new(transaction_params)
                   end

    @transaction.initiated_by_id = current_user.id if current_user
    @transaction.status ||= 'pending'
    @transaction.transaction_type ||= 'payment'

    if @transaction.save
      render json: @transaction, 
             serializer: TransactionDetailSerializer,
             status: :created
    else
      render json: { errors: @transaction.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # PATCH /transactions/:id
  def update
    if @transaction.update(transaction_params)
      render json: @transaction, serializer: TransactionDetailSerializer
    else
      render json: { errors: @transaction.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # POST /transactions/:id/process_payment
  def process_payment
    # Maintain existing simulation logic
    payment_successful = true # Replace with actual payment gateway logic

    if payment_successful
      @transaction.update(status: 'completed', processed_at: Time.current)
      render json: { 
        message: 'Payment processed successfully', 
        transaction: TransactionDetailSerializer.new(@transaction) 
      }
    else
      @transaction.update(
        status: 'failed',
        payment_gateway_response: { error: 'Payment failed' }
      )
      render json: { 
        error: 'Payment failed', 
        transaction: TransactionDetailSerializer.new(@transaction) 
      }, status: :unprocessable_entity
    end
  end

  # DELETE /transactions/:id
  def destroy
    @transaction.destroy
    head :no_content
  end

  private

  def set_transaction
    @transaction = Transaction.find(params[:id])
  end

  def set_school
    return unless params[:school_id]
    @school = School.find(params[:school_id])
  end

  def transaction_params
    params.require(:transaction).permit(
      # Existing params
      :user_id, 
      :school_id, 
      :amount,
      
      # New params
      :status,
      :transaction_type,
      :description,
      :payment_method,
      :student_id,
      :account_id,
      :metadata,
      payment_gateway_response: {}
    )
  end
end
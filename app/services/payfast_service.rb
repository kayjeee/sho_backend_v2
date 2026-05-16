# app/services/payfast_service.rb
class PayfastService
  class << self
    def generate_payment_url(transaction)
      # PayFast API credentials
      merchant_id = ENV['PAYFAST_MERCHANT_ID'] || Rails.application.credentials.dig(:payfast, :merchant_id)
      merchant_key = ENV['PAYFAST_MERCHANT_KEY'] || Rails.application.credentials.dig(:payfast, :merchant_key)
      
      # Base URL (sandbox for development)
      base_url = Rails.env.production? ? 
        'https://www.payfast.co.za' : 
        'https://sandbox.payfast.co.za'
      
      # Payment data
      payment_data = {
        merchant_id: merchant_id,
        merchant_key: merchant_key,
        return_url: transaction.metadata['return_url'],
        cancel_url: transaction.metadata['cancel_url'],
        notify_url: transaction.metadata['notify_url'],
        name_first: transaction.user&.name&.split&.first || 'Customer',
        name_last: transaction.user&.name&.split&.last || '',
        email_address: transaction.user&.email || '',
        m_payment_id: transaction.id.to_s,
        amount: transaction.amount.to_f,
        item_name: transaction.metadata['item_name'],
        item_description: "Subscription payment for #{transaction.subscription_tier} plan",
        custom_str1: transaction.user_id,
        custom_str2: transaction.subscription_tier,
        custom_str3: transaction.subscription_billing_cycle,
        subscription_type: 1,
        recurring_amount: transaction.amount.to_f,
        frequency: transaction.metadata['frequency'],
        cycles: 0
      }
      
      # Remove nil values
      payment_data.compact!
      
      # Generate signature
      payment_data[:signature] = generate_signature(payment_data)
      
      # Build URL
      query_string = payment_data.to_query
      "#{base_url}/eng/process?#{query_string}"
    end
    
    def generate_signature(data)
      # Sort the data alphabetically by key
      sorted_data = data.sort.to_h
      
      # Create the parameter string
      pf_param_string = sorted_data.map { |key, value| "#{key}=#{CGI.escape(value.to_s).gsub('+', '%20')}" }.join('&')
      
      # Add passphrase if present
      passphrase = ENV['PAYFAST_PASSPHRASE'] || Rails.application.credentials.dig(:payfast, :passphrase)
      pf_param_string += "&passphrase=#{CGI.escape(passphrase)}" if passphrase.present?
      
      # Generate MD5 hash
      Digest::MD5.hexdigest(pf_param_string)
    end
    
    def validate_ipn_notification(params)
      # Check if it's a valid PayFast notification
      return false unless params[:pf_payment_id].present?
      
      # Verify signature
      signature = params.delete(:signature)
      calculated_signature = generate_signature(params)
      
      if signature == calculated_signature
        # Additional validation by calling PayFast
        validate_with_payfast(params)
      else
        false
      end
    end
    
    def validate_with_payfast(params)
      # Send validation request to PayFast
      uri = URI.parse('https://sandbox.payfast.co.za/eng/query/validate')
      
      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = true
      
      request = Net::HTTP::Post.new(uri.path)
      request['Content-Type'] = 'application/x-www-form-urlencoded'
      
      # Prepare validation data
      validation_data = params.except(:action, :controller).to_query
      request.body = validation_data
      
      response = https.request(request)
      
      response.body.strip == 'VALID'
    end
  end
end
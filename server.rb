require 'sinatra'
require 'stripe'
require 'json'

Stripe.api_key = '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' 

set :root, File.dirname(__FILE__)
set :public_folder, -> { File.join(root, 'public') }
set :static, true
set :port, ENV['PORT'] || 4567
set :bind, '0.0.0.0'

get '/' do
  redirect '/index.html'
end

post '/create_location' do
  content_type 'application/json'
  data = JSON.parse(request.body.read)
  Stripe::Terminal::Location.create({
    display_name: data['display_name'],
    address: data['address']
  }).to_json
end

post '/register_reader' do
  content_type 'application/json'
  data = JSON.parse(request.body.read)
  Stripe::Terminal::Reader.create(
    location: data['location_id'],
    registration_code: 'simulated-s700',
    label: 'S700 Reader'
  ).to_json
end

post '/process_terminal_payment' do
  content_type 'application/json'
  data = JSON.parse(request.body.read)
  reader = Stripe::Terminal::Reader.process_payment_intent(
      data['reader_id'],
      payment_intent: data['payment_intent_id']
    )
  reader.to_json
end
post '/create_payment_intent' do
  content_type 'application/json'
  data = JSON.parse(request.body.read)
  
  mode = data['mode']

  params = {
    amount: data['amount'],
    currency: 'gbp',
    capture_method: 'automatic',
  }

  if mode == 'terminal'
    params[:payment_method_types] = ['card_present']
    params[:capture_method] = 'manual_preferred'
  elsif mode == 'online'
    params[:payment_method_types] = ['card', 'us_bank_account']
    
    params[:payment_method_options] = {
      us_bank_account: {
        verification_method: 'automatic',
        financial_connections: { permissions: ['payment_method', 'balances'] }
      },
      card: {
        request_three_d_secure: 'any' 
      }
    }
  end

  intent = Stripe::PaymentIntent.create(params)
  intent.to_json
end
post '/process_manual_online_payment' do
  content_type 'application/json'
  data = JSON.parse(request.body.read)

  begin
    card_details = {
      number: data['card_number'],
      exp_month: data['exp_month'],
      exp_year: data['exp_year']
    }
    card_details[:cvc] = data['cvc'] if data['cvc'] && !data['cvc'].empty?

    payment_method = Stripe::PaymentMethod.create({
      type: 'card',
      card: card_details
    })
    intent = Stripe::PaymentIntent.create({
      amount: data['amount'],
      currency: 'gbp',
      payment_method: payment_method.id,
      confirm: true,
      error_on_requires_action: true, 
      automatic_payment_methods: { enabled: true, allow_redirects: 'never' } 
    })

    intent.to_json

  rescue Stripe::CardError => e
    status 402
    { error: e.message, code: e.code, decline_code: e.decline_code }.to_json
  rescue Stripe::StripeError => e
    status 500
    { error: e.message }.to_json
  end
end
post '/confirm_online_payment' do
  content_type 'application/json'
  data = JSON.parse(request.body.read)
  
  intent = Stripe::PaymentIntent.retrieve(data['payment_intent_id'])
  intent = intent.confirm({ payment_method: data['payment_method_id'] }) if data['payment_method_id']
  
  intent.to_json
end

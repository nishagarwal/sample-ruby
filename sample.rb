require 'bundler/setup'
require 'json'
#wierd issue when loading zuora-ruby other gems word fine...
#require 'rubygems'
#require 'zuora-ruby'
require_relative '/Users/nagarwal/.rvm/gems/ruby-2.3.0/gems/zuora-ruby-0.5.0/lib/zuora.rb'
require_relative 'settings.rb'

@settings = Settings.new "config.yml"
################################### LOGIN ##################################
#
def client
  @client ||= Zuora::Client.new @settings.username, @settings.password
end
################################### PRODUCT CATALOG ##################################
#
def get_product_catalog
  response = client.get('/rest/v1/catalog/products?pageSize=40')
	body = response.body
  return body
end
#
#
def print_product_catalog
  body = get_product_catalog
  # puts JSON.pretty_generate(body)
  body['products'].each do |prod|
    puts prod['name']
  end
end
#
#
def get_product_rate_plans_for_product name
  body = get_product_catalog
  body['products'].each do |prod|
    prod['productRatePlans'].each do |prodRatePlan|
      return prodRatePlan if prodRatePlan['name'] == name
    end
  end
end
#################################### ACCOUNT ##################################
#
def create_account name, contact
	response = client.post(
    '/rest/v1/accounts',
    name: name,
    hpmCreditCardPaymentMethodId: 'b7979c8c3f0ef1bb014a7895844e1078',
    currency: 'USD',
    "autoPay": false,
    billCycleDay: '1',
    billToContact: contact
  )
	account_number = response.body['accountNumber']
	# puts response.body
	return account_number
end
#
#
def get_account account_number
	response = client.get('/rest/v1/accounts/'+account_number)
	# puts response.body
end
#
#
def subscribe name, contact, contract_effective_date, service_activation_date, product_rate_plan_id
  begin
    response = client.post(
      '/rest/v1/accounts',
      name: name,
      currency: 'USD',
      autoPay: false,
      billCycleDay: '1',
      # hpmCreditCardPaymentMethodId
      # this should be taken from hpm / this way is not PCI compliant
      creditCard: {
        cardType: 'Visa',
        cardNumber: '4111111111111111',
        expirationMonth: '12',
        expirationYear: '2050'
      },
      billToContact: contact,
      subscription: {
        initialTerm: "12",
        renewalTerm: "12",
        termType: "TERMED",
        autoRenew: false,
        contractEffectiveDate: contract_effective_date,
        serviceActivationDate: service_activation_date,
        subscribeToRatePlans:
          [
            {
              productRatePlanId: product_rate_plan_id
            }
          ],
        notes: "Test POST subscription from zuora-ruby-lib"
      }
    )
    puts response.body
    subscription_number = response.body['subscriptionNumber']
    return subscription_number
  rescue Zuora::Rest::ErrorResponse => err
    p err.response.body["reasons"]
  end
end
#################################### SUBSCRIPTION ##################################
#
def create_subscription account_number, contract_effective_date, product_rate_plan_id
  begin
  	response = client.post(
      '/rest/v1/subscriptions',
  		initialTerm: "12",
  		renewalTerm: "12",
  		termType: "TERMED",
  		autoRenew: false,
  		accountKey: account_number,
  		contractEffectiveDate: contract_effective_date,
  		subscribeToRatePlans:
  		  [
  		    {
  		      productRatePlanId: product_rate_plan_id
          }
  		  ],
  		notes: "Test POST subscription from zuora-ruby-lib",
      invoice: true,
      collect: false
    )
    # puts response.body
    subscription_number = response.body['subscriptionNumber']
    return subscription_number
  rescue Zuora::Rest::ErrorResponse => err
    p err.response.body["reasons"]
  end
  return
end

def get_subscription subscription_number
	response = client.get('/rest/v1/subscriptions/'+subscription_number)
	#puts response.body
	return response.body
end

def amend_subscription subscription_number, contract_effective_date, rate_plan_id, rate_plan_charge_id, price
  begin
  	response = client.put(
      '/rest/v1/subscriptions/'+subscription_number,
      notes: "Test UPDATE subscription from zuora-ruby",
      update:
  		  [
          {
            ratePlanId: rate_plan_id,
  		      contractEffectiveDate: contract_effective_date,
  		      chargeUpdateDetails:
  		        [
                {
                  ratePlanChargeId: rate_plan_charge_id,
  		            price: price
                }
              ]
          }
        ],
      invoice: true
    )
    # puts response.body
    subscription_number = response.body['subscription_number']
    return subscription_number
  rescue Zuora::Rest::ErrorResponse => err
    p err.response.body["reasons"]
  end
end
#
#
def cancel_subscription subscription_number, cancellation_effective_date
  begin
  	response = client.put(
      '/rest/v1/subscriptions/'+subscription_number+'/cancel',
  		cancellationPolicy: "SpecificDate",
  		cancellationEffectiveDate: cancellation_effective_date,
    )
  	# puts response.body
  rescue Zuora::Rest::ErrorResponse => err
    p err.response.body["reasons"]
  end
end
#################################### TESTS ##################################
# Creates an acocunt and subscription in Zuora with 
# CED=Today
# Plan = Medium Monthly Plan w Discount
#
def create_account_and_create_subscription account_name
  contact = {
    address1: '1051 E Hillsdale Blvd',
    city: 'Foster City',
    country: 'United States',
    firstName: 'John',
    lastName: 'Smith',
    zipCode: '94404',
    state: 'CA'
  }
	account_number = create_account account_name, contact
	puts '### Account created in Zuora with number: '+ account_number
  #get the rate plans for the product
	product_rate_plan = get_product_rate_plans_for_product 'Medium Monthly Plan w Discount'
  #create the subscription
	subscription_number = create_subscription(
    account_number,
    DateTime.now.strftime("%Y-%m-%d"),
    product_rate_plan['id']
  )
	puts '### Subscription created in Zuora with number: ' + subscription_number
  return subscription_number
end
#
#
def create_and_amend_subscription account_name
  subscription_number = create_account_and_create_subscription account_name
  #get the subscription
	subscription = get_subscription(subscription_number)
	ratePlanId = subscription['ratePlans'][0]['id']
  ratePlanChargeId = ''
  subscription['ratePlans'][0]['ratePlanCharges'].each do |ratePlanCharge|
    ratePlanChargeId = ratePlanCharge['id'] if ratePlanCharge['name'] == 'Medium Monthly Charge'
  end

	#ratePlanChargeId = subscription['ratePlans'][0]['ratePlanCharges'][1]['id']
  #create an amendment to change the charges price to 25
  amend_subscription(
    subscription_number,
    DateTime.now.strftime("%Y-%m-%d"),
    ratePlanId,
    ratePlanChargeId,
    25
  )
	puts '### Amendment created on subscription: ' + subscription_number
end
#
#
def create_and_cancel account_name
  subscription_number = create_account_and_create_subscription account_name
	cancel_subscription(
    subscription_number,
    DateTime.now.strftime("%Y-%m-%d")
  )
	puts '### Subscription cancelled: ' + subscription_number
end
#
# Creates an account and subscription using 2 calls (create account, create subscription)
# CED=Today, SAD=Today+10
# Plan = Medium Monthly Plan
#
def create_account_and_subscribe_single_call account_name
  contact = {
    address1: '1051 E Hillsdale Blvd',
    city: 'Foster City',
    country: 'United States',
    firstName: 'John',
    lastName: 'Smith',
    zipCode: '94404',
    state: 'CA'
  }
  #get the rate plans for the product
  product_rate_plan = get_product_rate_plans_for_product 'Medium Monthly Plan'
  myDate = DateTime.now + 10.days;
  #create an account and subscribe to a rate plan at the same time
  subscribe(
    account_name,
    contact,
    DateTime.now.strftime("%Y-%m-%d"),
    myDate.strftime("%Y-%m-%d"),
    product_rate_plan['id']
  )
end

def soap_query_accounts
  soap_client = Zuora::Soap::Client.new @settings.username, @settings.password
  response = soap_client.call! :query, "SELECT Id,Name FROM Account WHERE Id='b7976c9269722c0c014b3cb01d85717c'"
  puts response.to_h.envelope.body
end

#print_product_catalog
create_account_and_subscribe_single_call 'Demo Test 1 - 10 days trial'
create_account_and_create_subscription 'Demo Test 2 - 50% discount'
create_and_amend_subscription 'Demo Test 3 - amend'
create_and_cancel 'Demo Test 4 - cancel'
#soap_query_accounts
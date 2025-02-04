# frozen_string_literal: true

class HomeController < ApplicationController
  before_action :refresh_token, :date_range, :bling_order_items, :current_done_order_items, :set_monthly_revenue_estimation,
                :get_in_progress_order_items, :get_printed_order_items,
                :get_pending_order_items, :canceled_orders, only: :index
  include SheinOrdersHelper

  def index
    @shein_orders_count = SheinOrder.where("data ->> 'Status do pedido' = ?", 'Para ser coletado por SHEIN')
                                    .where(account_id: current_user.account.id)
                                    .distinct
                                    .count("data ->> 'Número do pedido'")

    @shein_pending_count = SheinOrder.where("data ->> 'Status do pedido' IN (?)", ['Pendente']).where(account_id: current_user.account.id)
                                     .distinct
                                     .count("data ->> 'Número do pedido'")

    @shein_orders = SheinOrder.where("data ->> 'Status do pedido' IN (?)",
                                     ['Para ser coletado por SHEIN', 'Pendente', 'Para ser enviado'])
                              .where(account_id: current_user.account.id)
    @expired_orders = @shein_orders.select { |order| order_status(order) == 'Atrasado' }
    @expired_orders_count = @expired_orders.count

    order_ids = @orders&.select { |order| order['loja']['id'] == 204_061_683 }&.map { |order| order['id'] }

    @mercado_envios_flex_counts = count_mercado_envios_flex(order_ids)

    @store_name = get_loja_name

    @loja_ids = [204_219_105, 203_737_982, 203_467_890, 204_061_683]

    @expires_at = format_last_update(@date_expires)

    @last_update = format_last_update(Time.current)

    @grouped_printed_order_items = BlingOrderItem.group_order_items(@printed_order_items)
    @grouped_pending_order_items = BlingOrderItem.group_order_items(@pending_order_items)
    @grouped_in_progress_order_items = BlingOrderItem.group_order_items(@in_progress_order_items)
  rescue StandardError => e
    Rails.logger.error(e.message)
    redirect_to home_last_updates_path
  end

  def last_updates
    @custumers = Customer.order(id: :desc).limit(10)
    @products = Product.order(id: :desc).limit(10)
  end

  private

  def date_range
    @first_date = params.try(:fetch, :bling_order_item, nil).try(:fetch, :initial_date, nil).try(:to_date).try(:beginning_of_day) || Time.zone.today.beginning_of_day
    @second_date = params.try(:fetch, :bling_order_item, nil).try(:fetch, :final_date, nil).try(:to_date).try(:end_of_day) || Time.zone.today.end_of_day
    @date_range = @first_date.to_date.beginning_of_day..@second_date.end_of_day
  end

  def bling_order_items
    base_query = BlingOrderItem.where(situation_id: BlingOrderItem::Status::WITHOUT_CANCELLED,
                                      account_id: current_user.account.id)
                               .date_range(@first_date, @second_date)

    @bling_order_items = BlingOrderItem.group_order_items(base_query)
  end

  def get_in_progress_order_items
    @in_progress_order_items = BlingOrderItem.where(situation_id: BlingOrderItem::Status::IN_PROGRESS,
                                                    account_id: current_user.account.id)
  end

  def finance_per_status
    @pendings = SheinOrder.where("data ->> 'Status do pedido' = ?", 'Pendente')
    @to_be_colected = SheinOrder.where("data ->> 'Status do pedido' = ?", 'Para ser coletado por SHEIN')
    @to_be_sent = SheinOrder.where("data ->> 'Status do pedido' = ?", 'Para ser enviado por SHEIN')
    @sent = SheinOrder.where("data ->> 'Status do pedido' = ?", 'Enviado')
  end

  def current_done_order_items
    base_query = BlingOrderItem.where(situation_id: [BlingOrderItem::Status::VERIFIED,
                                                     BlingOrderItem::Status::CHECKED],
                                      alteration_date: @date_range,
                                      account_id: current_user.account.id)
    @current_done_order_items = BlingOrderItem.group_order_items(base_query)
  end

  def get_printed_order_items
    @printed_order_items = BlingOrderItem.where(situation_id: BlingOrderItem::Status::PRINTED,
                                                account_id: current_user.account.id)
  end

  def get_pending_order_items
    @pending_order_items = BlingOrderItem.where(situation_id: BlingOrderItem::Status::PENDING,
                                                account_id: current_user.account.id)
  end

  def canceled_orders
    base_query = BlingOrderItem.where(situation_id: BlingOrderItem::Status::CANCELED,
                                      account_id: current_user.account.id)
                               .date_range(@first_date, @second_date)

    @canceled_orders = BlingOrderItem.group_order_items(base_query)
  end

  def set_monthly_revenue_estimation
    @monthly_revenue_estimation = RevenueEstimation.current_month.take
  end

  def count_mercado_envios_flex(order_ids)
    # TODO, get it from the database directly.
    return if order_ids.blank?

    counter = 0
    order_ids.each do |order_id|
      response = Services::Bling::FindOrder.call(id: order_id, order_command: 'find_order',
                                                 tenant: current_user.account.id)
      order = response['data']

      shipping = order['transporte']
      shipping_service = shipping['volumes'][0]['servico']
      counter += 1 if shipping_service == 'Mercado Envios Flex'
    rescue StandardError => e
      Rails.logger.error('Not Mercado Envios Flex')
      Rails.logger.error(e.message)
    end
    counter
  end

  def fetch_order_data(order_id)
    Services::Bling::FindOrder.call(id: order_id, order_command: 'find_order',
                                    tenant: current_user.account.id)
  end

  def format_last_update(time)
    time&.strftime('%d-%m-%Y %H:%M:%S')
  end

  def token_expires_at
    BlingDatum.find_by(account_id: current_tenant.id).try(:expires_at)
  end

  def refresh_token
    @date_expires = token_expires_at
    return if @date_expires.blank? || (@date_expires > DateTime.now && !Rails.env.eql?('production'))

    refresh_token = BlingDatum.find_by(account_id: current_tenant.id).refresh_token
    client_id = ENV['CLIENT_ID']
    client_secret = ENV['CLIENT_SECRET']
    credentials = Base64.strict_encode64("#{client_id}:#{client_secret}")
    @expires_at = format_last_update(@date_expires)
    @last_update = format_last_update(Time.current)
    begin
      @response = HTTParty.post('https://bling.com.br/Api/v3/oauth/token',
                                body: {
                                  grant_type: 'refresh_token',
                                  refresh_token:
                                },
                                headers: {
                                  'Content-Type' => 'application/x-www-form-urlencoded',
                                  'Accept' => '1.0',
                                  'Authorization' => "Basic #{credentials}"
                                })

      verify_tokens
    rescue StandardError => e
      Rails.logger.error(e.message)
    end
  end

  def verify_tokens
    tokens = BlingDatum.find_by(account_id: current_tenant.id)
    tokens.update(access_token: @response['access_token'],
                  expires_in: @response['expires_in'],
                  expires_at: Time.zone.now + @response['expires_in'].seconds,
                  token_type: @response['token_type'],
                  scope: @response['scope'])
  end

  def get_loja_name
    {
      204_219_105 => 'Shein',
      203_737_982 => 'Shopee',
      203_467_890 => 'Simplo 7',
      204_061_683 => 'Mercado Livre'
    }
  end
end

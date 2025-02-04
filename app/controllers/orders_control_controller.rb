# frozen_string_literal: true

class OrdersControlController < ApplicationController
  def show_orders_control
    @send_orders = []
    list_orders
    # unique_order
    @orders.each do |order|
      # if order['Wspedido']['pedidostatus_id'] == '23' || order['Wspedido']['pedidostatus_id'] == '3'
      @send_orders << order
      # end
    end
    @send_orders
  end

  def show_orders_products_stock
    @products = Product.includes(:purchase_products, simplo_items: [:simplo_order])
                       .where(simplo_orders: { order_status: %w[2 30 31] })
                       .where(account_id: current_tenant.id)
                       .order(custom_id: :desc)
  end
  

  def show_pending_orders
    situation_id = params[:situation_id]
    store_id = params[:store_id]
  
    if situation_id.present?
      cleaned_situation_ids = situation_id.split(',').map(&:to_i)
    else
      cleaned_situation_ids = BlingOrderItem::Status::PENDING
    end
    
    if store_id.present?
      @pending_order_items = BlingOrderItem.where(situation_id: cleaned_situation_ids, store_id: store_id)
    else
      @pending_order_items = BlingOrderItem.where(situation_id: cleaned_situation_ids)
    end
    respond_to do |format|
      format.html # show.html.erb
      format.csv { send_data generate_csv(@pending_order_items), filename: "pending-orders-#{Date.today}.csv" }
    end
  end

  def show_orders_business_day
    @simplo_orders = SimploOrder.where(order_status: %w[2 30 31]).order(order_id: :asc)
    @calendar = SimploOrder.calendar
  end

  def post_mail_control
    @post_data = PostDatum.all
  end

  def import_post_mail; end

  private

  def generate_csv(pending_order_items)
    # Filter out items where `items` is nil
    filtered_items = pending_order_items.select { |item| item.items.present? }
  
    # Group the filtered items by 'codigo'
    grouped_items = filtered_items.group_by { |item| item.items['codigo'] }
  
    CSV.generate(headers: true) do |csv|
      csv << ['Codigo', 'Total Quantity'] # Customize your headers here
  
      grouped_items.each do |codigo, items|
        # Sum only the quantities of items with a non-nil 'quantidade'
        total_quantity = items.sum { |item| item.items['quantidade'].to_i }
        csv << [codigo, total_quantity] # Add each group's code and total quantity
      end
    end
  end
  
  
  def list_orders
    @orders = []
    (1..20).each do |i|
      @order_page = HTTParty.get("https://purchasestore.com.br/ws/wspedidos.json?page=#{i}",
                                 headers: { content: 'application/json',
                                            Appkey: '' })
      @order_page['result'].each do |order_page|
        @orders << order_page
      end
    end
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

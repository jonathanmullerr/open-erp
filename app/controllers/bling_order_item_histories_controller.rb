# frozen_string_literal: true
# a
# There is a necessity to know the revenue from the last 15 days
# In order to take better commercial decisions.
class BlingOrderItemHistoriesController < ApplicationController
  before_action :date_range, :paid_bling_order_items, :day_quantities_presenter,
                only: %i[day_quantities]
  before_action :daily_revenue, :canceled_revenue, only: :index

  def index;end

  def day_quantities
    render json: @paid_items_presentable
  end

  def daily_revenue
    @initial_date = params.fetch('bling_order', initial_date: Date.today.strftime).fetch('initial_date')
    @final_date = params.fetch('bling_order', final_date: Date.today.strftime).fetch('final_date')
    @daily_date_range_filter = { initial_date: @initial_date, final_date: @final_date }
    @bling_order_items = BlingOrderItem.where(situation_id: [BlingOrderItem::Status::PAID],
                                              account_id: current_user.account.id)
    @daily_revenue = DailyRevenueReport.new(@bling_order_items, @daily_date_range_filter).presentable
    @daily_revenue = @daily_revenue.to_json
  end

  private

  def date_range
    initial_date = (Date.today - 15.days).beginning_of_day
    final_date = Date.today.end_of_day
    @date_range = initial_date..final_date
  end

  def canceled_revenue
    @canceled_bling_order_items = BlingOrderItem.where(situation_id: [BlingOrderItem::Status::CANCELED],
                                              account_id: current_user.account.id)
    @canceled_revenue = DailyRevenueReport.new(@canceled_bling_order_items, @daily_date_range_filter).presentable
    @canceled_revenue = @canceled_revenue.to_json
  end

  def paid_bling_order_items
    @paid_bling_order_items = BlingOrderItem.where(date: date_range, situation_id: [BlingOrderItem::Status::PAID],
                                                   account_id: current_user.account.id)
  end

  def day_quantities_presenter
    @paid_items_presentable = BlingOrderItemHistoriesPresenter.new(@paid_bling_order_items).presentable
  end
end

Spree::ShippingRate.class_eval do
  def name
    read_attribute(:name) || self.shipping_method.name
  end
end
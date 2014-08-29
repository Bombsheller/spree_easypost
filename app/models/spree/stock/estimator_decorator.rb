Spree::Stock::Estimator.class_eval do
  def shipping_rates(package)
    order = package.order

    from_address = process_address(package.stock_location)
    to_address = process_address(order.ship_address)
    parcel = build_parcel(package)
    shipment_info_hash = build_shipment_info_hash(from_address, to_address, parcel)

    shipment_info_hash[:customs_info] = build_customs_info(package) if going_international?(package.stock_location, order.ship_address)

    shipment = build_shipment(shipment_info_hash)
    rates = shipment.rates.sort_by { |r| r.rate.to_i }

    if rates.any?
      rates.each do |rate|
        package.shipping_rates << Spree::ShippingRate.new(
          :name => "#{rate.carrier} #{rate.service}",
          :cost => rate.rate,
          :easy_post_shipment_id => rate.shipment_id,
          :easy_post_rate_id => rate.id
        )
      end

      # Sets cheapest rate to be selected by default
      package.shipping_rates.first.selected = true

      package.shipping_rates
    else
      []
    end
  end

  private

  def process_address(address)
    ep_address_attrs = {}
    # Stock locations do not have "company" attributes,
    ep_address_attrs[:company] = if address.respond_to?(:company)
      address.company
    else
      Spree::Config[:site_name]
    end
    ep_address_attrs[:name] = address.full_name if address.respond_to?(:full_name)
    ep_address_attrs[:street1] = address.address1
    ep_address_attrs[:street2] = address.address2
    ep_address_attrs[:city] = address.city
    ep_address_attrs[:state] = address.state ? address.state.abbr : address.state_name
    ep_address_attrs[:zip] = address.zipcode
    ep_address_attrs[:country] = address.country.iso
    ep_address_attrs[:phone] = address.phone if Spree::StockLocation.find_by_phone(address.phone)

    ::EasyPost::Address.create(ep_address_attrs)
  end

  def build_parcel(package)
    total_weight = package.contents.sum do |item|
      item.quantity * item.variant.weight
    end

    parcel_options = {:weight => total_weight}
    parcel_options[:predefined_package] = Spree::Config.preferred_international_packaging if Spree::Config.preferred_international_packaging

    parcel = ::EasyPost::Parcel.create(parcel_options)
  end

  def going_international? from_address, to_address
    !(from_address.country.iso == to_address.country.iso)
  end

  # See https://www.easypost.com/customs-guide. In Bombsheller's case we only have one product,
  # so the customs info is stored in Spree settings. For others, the product or variant
  # is a better place for tariff number.
  def build_customs_info package
    customs_items = []
    line_items = package.contents.collect(&:line_item)
    if Spree::Config.harmonized_tariff_number # Only shipping one product
      customs_items << EasyPost::CustomsItem.create(
        description: Spree::Config.item_customs_description,
        quantity: line_items.collect(&:quantity).inject(:+).to_i,
        value: line_items.collect(&:variant).collect(&:price).inject(:+).to_i,
        weight: line_items.collect(&:variant).collect(&:weight).inject(:+).to_i,
        hs_tariff_number: Spree::Config.harmonized_tariff_number,
        origin_country: package.stock_location.country.iso)
    else
      # TODO: Group by tariff number and perform the above steps with each group.
    end

    customs_info = EasyPost::CustomsInfo.create(
      eel_pfc: package.order.ship_address.country.iso == 'CA' ? 'NOEEI 30.36' : 'NOEEI 30.37(a)',
      customs_certify: true,
      customs_signer: Spree::Config.customs_signer,
      contents_type: 'merchandise',
      customs_items: customs_items
      )
  end

  def build_shipment_info_hash(from_address, to_address, parcel)
    {
      :to_address => to_address,
      :from_address => from_address,
      :parcel => parcel
    }
  end

  def build_shipment(shipment_info_hash)
    shipment = ::EasyPost::Shipment.create(shipment_info_hash)
  end

end

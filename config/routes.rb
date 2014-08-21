Spree::Core::Engine.routes.draw do
  # Add your extension routes here
  namespace :admin do
    resources :shipments do
      member do
        get :shipping_label
      end
    end
  end
end

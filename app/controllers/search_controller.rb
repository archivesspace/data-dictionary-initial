class SearchController < ApplicationController
  def show
    if params[:query].present?
      @fields = Field.search_by_keyword(params[:query])
    else
     @fields = Field.order(:field_table, :field_name)
    end
  end
end

class Projects::ServicesController < Projects::ApplicationController
  include ServiceParams

  # Authorize
  before_action :authorize_admin_project!
  before_action :service, only: [:edit, :update, :test]

  respond_to :html

  layout "project_settings"

  def index
    @project.build_missing_services
    @services = @project.services.visible.reload
  end

  def edit
  end

  def update
    if @service.update_attributes(service_params)
      redirect_to(
        edit_namespace_project_service_path(@project.namespace, @project,
                                            @service.to_param, notice:
                                            'Successfully updated.')
      )
    else
      render 'edit'
    end
  end

  def test
    data = @service.test_data(project, current_user)
    outcome = @service.test(data)

    if outcome[:success]
      message = { notice: 'We sent a request to the provided URL' }
    else
      error_message = "We tried to send a request to the provided URL but an error occurred"
      error_message << ": #{outcome[:result]}" if outcome[:result].present?
      message = { alert: error_message }
    end

    redirect_back_or_default(options: message)
  end

  private

  def service
    @service ||= @project.services.find { |service| service.to_param == params[:id] }
  end

  def service_params
    dynamic_params = []
    dynamic_params.concat(@service.event_channel_names) if @service.is_a?(SlackService)

    service_params = params.require(:service).permit(ALLOWED_PARAMS + dynamic_params)

    FILTER_BLANK_PARAMS.each do |param|
      service_params.delete(param) if service_params[param].blank?
    end

    service_params
  end
end

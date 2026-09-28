module Enterprise::AsyncDispatcher
  def listeners
    super + [
      CaptainListener.instance,
      CaptainLearningListener.instance
      Captain::ReportingEventListener.instance
    ]
  end
end

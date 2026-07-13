module Enterprise::AsyncDispatcher
  def listeners
    super + [
      CaptainListener.instance,
      CaptainLearningListener.instance
    ]
  end
end

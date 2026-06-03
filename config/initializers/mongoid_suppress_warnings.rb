# Suppress Mongoid "Overwriting existing field" warnings
Mongoid.logger.level = Logger::ERROR
Mongo::Logger.logger.level = Logger::ERROR

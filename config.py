import os
from dotenv import load_dotenv

load_dotenv()

class Config:
    # Database configuration
    DB_HOST = os.environ.get('DB_HOST', 'database-eva-service')
    DB_USER = os.environ.get('DB_USER', 'root')
    DB_PASSWORD = os.environ.get('DB_PASSWORD', 'pCUCW1!9ByEsds9vooAi')
    DB_NAME = os.environ.get('DB_NAME', 'databasenjd_db')
    DB_PORT = int(os.environ.get('DB_PORT', 3306))
    
    # API configuration
    API_KEY = os.environ.get('API_KEY', 'your-secret-api-key')
    
    # Flask configuration
    SECRET_KEY = os.environ.get('SECRET_KEY', 'your-secret-key')
    DEBUG = os.environ.get('DEBUG', 'true').lower() == 'true'
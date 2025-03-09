-- Create database if it doesn't exist
CREATE DATABASE IF NOT EXISTS apple_id_db;
USE apple_id_db;

-- Create accounts table
CREATE TABLE IF NOT EXISTS accounts (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(255) NOT NULL,
  password VARCHAR(255) NOT NULL,
  country VARCHAR(50) NOT NULL,
  check_time DATETIME NOT NULL,
  status VARCHAR(50) NOT NULL
);

-- Create metadata table
CREATE TABLE IF NOT EXISTS metadata (
  id INT AUTO_INCREMENT PRIMARY KEY,
  key_name VARCHAR(50) UNIQUE NOT NULL,
  value TEXT NOT NULL,
  updated_at DATETIME NOT NULL
);

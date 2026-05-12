// types.go — Shared type definitions
// FIXME: error handling not standardized

package main

import (
	"encoding/json"
	"fmt"
	"time"
)

// User represents an application user
// TODO: add role-based access control
type User struct {
	ID        int       `json:"id"`
	Username  string    `json:"username"`
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"created_at"`
	IsActive  bool      `json:"is_active"`
}

// Validate checks user fields
func (u *User) Validate() error {
	if u.Username == "" {
		return fmt.Errorf("username is required")
	}
	if u.Email == "" {
		return fmt.Errorf("email is required") // FIXME: should validate email format
	}
	return nil
}

// ToJSON serializes user to JSON
func (u *User) ToJSON() ([]byte, error) {
	// TODO: add custom JSON marshaling for time fields
	return json.Marshal(u)
}

// Product represents a sellable item
type Product struct {
	ID       int     `json:"id"`
	Name     string  `json:"name"`
	Price    float64 `json:"price"` // FIXME: use decimal for currency
	Category string  `json:"category"`
}

// OrderProcessor handles order creation
type OrderProcessor struct {
	dbURL string
}

// CreateOrder creates a new order
func (op *OrderProcessor) CreateOrder(userID int, productIDs []int) error {
	// FIXME: no transaction support
	fmt.Printf("Creating order for user %d with products %v\n", userID, productIDs)
	return nil
}

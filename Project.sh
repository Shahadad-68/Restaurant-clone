#!/bin/bash

# Always resolve files relative to where the script lives,
# regardless of which directory you run it from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CASH_FILE="$SCRIPT_DIR/cash.txt"
MENU_FILE="$SCRIPT_DIR/menu.txt"
ORDERS_FILE="$SCRIPT_DIR/orders.txt"
DISCOUNT_FILE="$SCRIPT_DIR/discounts.txt"

if [ ! -f $CASH_FILE ]; then
    echo "0" > $CASH_FILE
fi

if [ ! -f $MENU_FILE ]; then
    touch $MENU_FILE
fi

if [ ! -f $ORDERS_FILE ]; then
    touch $ORDERS_FILE
fi

# Initialize discounts file with default rules if not exists
if [ ! -f "$DISCOUNT_FILE" ]; then
    echo "500 5" > "$DISCOUNT_FILE"
    echo "1000 10" >> "$DISCOUNT_FILE"
fi

# NEW FEATURE: Ensure cash file always has a valid numeric value.
ensure_cash_valid() {
    if [ ! -f "$CASH_FILE" ]; then
        echo "0" > "$CASH_FILE"
        return
    fi

    current_cash_value=$(cat "$CASH_FILE" 2>/dev/null)
    if [ -z "$current_cash_value" ] || ! [[ "$current_cash_value" =~ ^[0-9]+$ ]]; then
        echo "0" > "$CASH_FILE"
    fi
}

# NEW FEATURE: Initialize/repair cash content at startup.
ensure_cash_valid

# NEW FEATURE: Input validation helper for positive integers (item number, quantity).
is_positive_integer() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

# NEW FEATURE: Input validation helper for numeric values (price).
is_number() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

welcome_screen() {
    clear
    # NEW FEATURE: Better UI separator for readability.
    echo "================================="
    echo " Welcome to Restaurant Management System "
    echo "================================="
    echo
    echo "1. Admin Login"
    echo "2. Customer Login"
    echo "3. Exit"
    echo
    read -p "Please choose an option: " option
    case $option in
        1) admin_login ;;
        2) customer_login ;;
        3) exit_screen ;;
        *) echo "Invalid option!" ; welcome_screen ;;
    esac
}

admin_login() {
    clear
    read -p "Enter Admin Username: " admin_user
    read -s -p "Enter Admin Password: " admin_pass
    echo
    if [[ "$admin_user" == "admin" && "$admin_pass" == "pass" ]]; then
        admin_menu
    else
        echo "Invalid login details!"
        welcome_screen
    fi
}

admin_menu() {
    clear
    echo "============================="
    echo "        Admin Menu "
    echo "============================="
    echo
    echo "1. View Cash"
    echo "2. View Pending Orders"
    echo "3. Order History"
    echo "4. View Menu"
    echo "5. Add New Item to Menu"
    echo "6. Delete Item from Menu"
    echo "7. Edit Item from Menu"
    echo "8. Edit Discounts"
    echo "9. View Total Number of Orders"
    echo "10. Logout"
    echo
    read -p "Please choose an option: " option
    case $option in
        1) view_cash ;;
        2) view_orders ;;
        3) order_history ;;
        4) view_menu ;;
        5) add_item ;;
        6) delete_item ;;
        7) edit_item ;;
        8) edit_discounts ;;
        9) view_total_orders ;;
        10) welcome_screen ;;
        *) echo "Invalid option!" ; admin_menu ;;
    esac
}

view_cash() {
    clear
    # NEW FEATURE: Ensure cash value is always valid before display.
    ensure_cash_valid
    echo "============================="
    echo "        Cash Balance "
    echo "============================="
    echo "Total Cash: "
    cat $CASH_FILE
    echo "============================="
    echo
    read -p "Press any key to return to Admin Menu..." key
    admin_menu
}

view_orders() {
    clear
    echo "============================="
    echo "      Pending Orders "
    echo "============================="

    if [ ! -s "$ORDERS_FILE" ]; then
        echo "No orders found."
        echo "============================="
        echo
        read -p "Press any key to return to Admin Menu..." key
        admin_menu
        return
    fi

    pending=$(awk '
    /^Order ID:/ { block=$0"\n"; in_block=1; next }
    in_block {
        block=block $0"\n"
        if ($0 ~ /^=============================$/) {
            if (block ~ /\nStatus: Pending\n/) printf "%s", block
            in_block=0; block=""
        }
    }' "$ORDERS_FILE")

    if [ -z "$pending" ]; then
        echo "No pending orders."
        echo "============================="
        echo
        read -p "Press any key to return to Admin Menu..." key
        admin_menu
        return
    fi

    echo "$pending"
    echo "============================="
    echo
    echo "1. Accept an Order"
    echo "2. Cancel an Order"
    echo "3. Back"
    echo
    read -p "Please choose an option: " option
    case $option in
        1) accept_order ;;
        2) cancel_order ;;
        3) admin_menu ;;
        *) echo "Invalid option!" ; view_orders ;;
    esac
}

accept_order() {
    clear
    echo "============================="
    echo "       Accept Order "
    echo "============================="
    read -p "Enter Order ID to accept: " order_id

    if ! grep -q "^Order ID: $order_id$" "$ORDERS_FILE"; then
        echo "Order ID not found."
        echo
        read -p "Press any key to go back..." key
        view_orders
        return
    fi

    order_status=$(awk -v oid="$order_id" '
    /^Order ID:/ { if ($3 == oid) found=1 }
    found && /^Status:/ { print $2; exit }
    ' "$ORDERS_FILE")

    if [[ "$order_status" != "Pending" ]]; then
        echo "This order is not pending."
        echo
        read -p "Press any key to go back..." key
        view_orders
        return
    fi

    order_total=$(awk -v oid="$order_id" '
    /^Order ID:/ { if ($3 == oid) found=1 }
    found && /^Total Price:/ { print $3; found=0 }
    ' "$ORDERS_FILE")

    # Mark as Accepted
    awk -v oid="$order_id" '
    /^Order ID:/ { if ($3 == oid) mark=1 }
    mark && /^Status: Pending/ { sub(/Pending/, "Accepted"); mark=0 }
    { print }
    ' "$ORDERS_FILE" > "$ORDERS_FILE.tmp"
    mv "$ORDERS_FILE.tmp" "$ORDERS_FILE"

    # Add cash
    ensure_cash_valid
    current_cash=$(cat "$CASH_FILE")
    new_cash=$((current_cash + order_total))
    echo "$new_cash" > "$CASH_FILE"

    echo "Order ID $order_id has been accepted."
    echo "Cash updated: +$order_total (Total: $new_cash)"
    echo
    read -p "Press any key to return to Admin Menu..." key
    admin_menu
}

cancel_order() {
    clear
    echo "============================="
    echo "       Cancel Order "
    echo "============================="
    read -p "Enter Order ID to cancel: " order_id

    if ! grep -q "^Order ID: $order_id$" "$ORDERS_FILE"; then
        echo "Order ID not found."
        echo
        read -p "Press any key to go back..." key
        view_orders
        return
    fi

    order_status=$(awk -v oid="$order_id" '
    /^Order ID:/ { if ($3 == oid) found=1 }
    found && /^Status:/ { print $2; exit }
    ' "$ORDERS_FILE")

    if [[ "$order_status" != "Pending" ]]; then
        echo "This order is not pending."
        echo
        read -p "Press any key to go back..." key
        view_orders
        return
    fi

    read -p "Are you sure you want to cancel Order ID $order_id? (yes/no): " confirm
    if [[ "$confirm" == "yes" ]]; then
        awk -v oid="$order_id" '
        /^Order ID:/ { if ($3 == oid) mark=1 }
        mark && /^Status: Pending/ { sub(/Pending/, "Cancelled"); mark=0 }
        { print }
        ' "$ORDERS_FILE" > "$ORDERS_FILE.tmp"
        mv "$ORDERS_FILE.tmp" "$ORDERS_FILE"
        echo "Order ID $order_id has been cancelled."
    else
        echo "Operation cancelled."
    fi

    echo
    read -p "Press any key to return to Admin Menu..." key
    admin_menu
}

order_history() {
    clear
    echo "============================="
    echo "       Order History "
    echo "============================="

    if [ ! -s "$ORDERS_FILE" ]; then
        echo "No orders found."
        echo "============================="
        echo
        read -p "Press any key to return to Admin Menu..." key
        admin_menu
        return
    fi

    result=$(awk '
    /^Order ID:/ { block=$0"\n"; in_block=1; next }
    in_block {
        block=block $0"\n"
        if ($0 ~ /^=============================$/) {
            if (block ~ /\nStatus: Accepted\n/) printf "%s", block
            in_block=0; block=""
        }
    }' "$ORDERS_FILE")

    if [ -z "$result" ]; then
        echo "No accepted orders yet."
    else
        echo "$result"
    fi

    echo "============================="
    echo
    read -p "Press any key to return to Admin Menu..." key
    admin_menu
}

view_menu() {
    clear
    echo "============================="
    echo "           Menu "
    echo "============================="
    # NEW FEATURE: Basic error handling when menu is empty.
    if [ ! -s "$MENU_FILE" ]; then
        echo "Menu is empty"
    else
        cat $MENU_FILE; echo
    fi
    echo "============================="
    echo
    read -p "Press any key to return to Admin Menu..." key
    admin_menu
}

add_item() {
    clear
    if [ -s $MENU_FILE ]; then
        highest_item_number=$(awk -F ' - ' '{print $1}' $MENU_FILE | sort -n | tail -1)
    else
        highest_item_number=0
    fi
    new_item_number=$((highest_item_number + 1))
    
    read -p "Enter Item Name: " item_name
    read -p "Enter Item Description: " item_desc
    read -p "Enter Item Price: " item_price

    # NEW FEATURE: Prevent duplicate item names (case-insensitive).
    if grep -i -q " - $item_name - " "$MENU_FILE"; then
        echo "Item with the same name already exists."
        echo
        read -p "Press any key to return to Admin Menu..." key
        admin_menu
        return
    fi

    # NEW FEATURE: Validate price as numeric input.
    if ! is_number "$item_price"; then
        echo "Invalid price. Please enter a number."
        echo
        read -p "Press any key to return to Admin Menu..." key
        admin_menu
        return
    fi

    echo "Adding item: $new_item_number - $item_name - $item_desc - $item_price"
    # Ensure file ends with a newline before appending
    if [ -s "$MENU_FILE" ] && [ "$(tail -c 1 "$MENU_FILE" | wc -l)" -eq 0 ]; then
        echo "" >> "$MENU_FILE"
    fi
    echo "$new_item_number - $item_name - $item_desc - $item_price" >> $MENU_FILE

    echo
    echo "Item added to menu."
    echo
    read -p "Press any key to return to Admin Menu..." key
    
    admin_menu
}

delete_item() {
    clear
    echo "============================="
    echo " Menu "
    echo "============================="
    # NEW FEATURE: Basic error handling when menu is empty.
    if [ ! -s "$MENU_FILE" ]; then
        echo "Menu is empty"
        echo "============================="
        echo
        read -p "Press any key to return to Admin Menu..." key
        admin_menu
        return
    fi
    cat $MENU_FILE; echo
    echo "============================="
    
    read -p "Enter the exact Item Number to delete: " item_number

    # NEW FEATURE: Validate item number as positive integer.
    if ! is_positive_integer "$item_number"; then
        echo "Invalid item number. Please enter a number."
        echo
        read -p "Press any key to return to Admin Menu..." key
        admin_menu
        return
    fi
    
    echo "Item number entered: '$item_number'"
    
    if grep -q "^$item_number - " $MENU_FILE; then
        echo "Item found. Deleting..."
        sed -i "/^$item_number -/d" $MENU_FILE
        awk '{ if ($1 > n) { $1 = $1 - 1 } print }' n="$item_number" $MENU_FILE > $MENU_FILE.tmp
        mv $MENU_FILE.tmp $MENU_FILE
        echo
        echo "Item deleted successfully."
    else
        echo "Error deleting item. Item number '$item_number' not found in menu."
    fi
    
    echo
    read -p "Press any key to return to Admin Menu..." key
    admin_menu
}

edit_item() {
    clear
    echo "============================="
    echo " Menu "
    echo "============================="
    # NEW FEATURE: Basic error handling when menu is empty.
    if [ ! -s "$MENU_FILE" ]; then
        echo "Menu is empty"
        echo "============================="
        echo
        read -p "Press any key to return to Admin Menu..." key
        admin_menu
        return
    fi
    cat $MENU_FILE; echo
    echo "============================="
    
    read -p "Enter the exact Item Number to edit: " item_number

    # NEW FEATURE: Validate item number as positive integer.
    if ! is_positive_integer "$item_number"; then
        echo "Invalid item number. Please enter a number."
        echo
        read -p "Press any key to return to Admin Menu..." key
        admin_menu
        return
    fi
    
    echo "Item number entered: '$item_number'"
    
    if grep -q "^$item_number - " $MENU_FILE; 
    then
        echo "Item found. Editing..."

        tmp_file=$(mktemp)
        
        read -p "Enter new Item Name: " new_item_name
        read -p "Enter new Item Description: " new_item_desc
        read -p "Enter new Item Price: " new_item_price

        # NEW FEATURE: Validate price as numeric input.
        if ! is_number "$new_item_price"; then
            echo "Invalid price. Please enter a number."
            echo
            read -p "Press any key to return to Admin Menu..." key
            admin_menu
            return
        fi
        
        sed "/^$item_number -/d" $MENU_FILE > $tmp_file
        echo "$item_number - $new_item_name - $new_item_desc - $new_item_price" >> $tmp_file
        mv $tmp_file $MENU_FILE
        
        sort -n -o $MENU_FILE $MENU_FILE
        echo
        echo "Item edited successfully."
    else
        echo
        echo "Error editing item. Item number '$item_number' not found in menu."
    fi
    
    echo
    read -p "Press any key to return to Admin Menu..." key
    admin_menu
}



edit_discounts() {
    clear
    echo "============================="
    echo "        Discounts "
    echo "============================="
    echo
    echo "1. Show Existing Discounts"
    echo "2. Add Discount Rule"
    echo "3. Edit Existing Rule"
    echo "4. Delete a Rule"
    echo "5. Back"
    echo
    read -p "Please choose an option: " option
    case $option in
        1) show_discounts ;;
        2) add_discount ;;
        3) edit_discount ;;
        4) delete_discount ;;
        5) admin_menu ;;
        *) echo "Invalid option!" ; edit_discounts ;;
    esac
}

show_discounts() {
    clear
    echo "============================="
    echo "    Existing Discounts "
    echo "============================="
    if [ ! -s "$DISCOUNT_FILE" ]; then
        echo "No discount rules found."
    else
        awk '{printf "Order >= %s tk  =>  %s%% discount\n", $1, $2}' "$DISCOUNT_FILE"
    fi
    echo "============================="
    echo
    read -p "Press any key to go back..." key
    edit_discounts
}

add_discount() {
    clear
    echo "============================="
    echo "      Add Discount Rule "
    echo "============================="
    read -p "Minimum order amount: " min_amount
    if ! is_number "$min_amount"; then
        echo "Invalid amount."
        read -p "Press any key to go back..." key
        edit_discounts
        return
    fi
    read -p "Discount percentage: " percent
    if ! is_number "$percent"; then
        echo "Invalid percentage."
        read -p "Press any key to go back..." key
        edit_discounts
        return
    fi
    # Check for duplicate threshold
    if grep -q "^$min_amount " "$DISCOUNT_FILE"; then
        echo "A rule for this amount already exists. Use Edit instead."
        read -p "Press any key to go back..." key
        edit_discounts
        return
    fi
    echo "$min_amount $percent" >> "$DISCOUNT_FILE"
    # Keep sorted by amount ascending
    sort -n -o "$DISCOUNT_FILE" "$DISCOUNT_FILE"
    echo "Discount rule added: orders >= $min_amount tk get $percent% off."
    echo
    read -p "Press any key to go back..." key
    edit_discounts
}

edit_discount() {
    clear
    echo "============================="
    echo "     Edit Discount Rule "
    echo "============================="
    if [ ! -s "$DISCOUNT_FILE" ]; then
        echo "No rules to edit."
        read -p "Press any key to go back..." key
        edit_discounts
        return
    fi
    awk '{printf "%s: Order >= %s tk  =>  %s%% discount\n", NR, $1, $2}' "$DISCOUNT_FILE"
    echo
    read -p "Enter rule number to edit: " rule_num
    if ! is_positive_integer "$rule_num"; then
        echo "Invalid input."
        read -p "Press any key to go back..." key
        edit_discounts
        return
    fi
    total_rules=$(wc -l < "$DISCOUNT_FILE")
    if [ "$rule_num" -gt "$total_rules" ]; then
        echo "Rule not found."
        read -p "Press any key to go back..." key
        edit_discounts
        return
    fi
    read -p "New minimum order amount: " new_amount
    if ! is_number "$new_amount"; then
        echo "Invalid amount."
        read -p "Press any key to go back..." key
        edit_discounts
        return
    fi
    read -p "New discount percentage: " new_percent
    if ! is_number "$new_percent"; then
        echo "Invalid percentage."
        read -p "Press any key to go back..." key
        edit_discounts
        return
    fi
    awk -v rn="$rule_num" -v na="$new_amount" -v np="$new_percent" \
        'NR==rn { print na " " np; next } { print }' "$DISCOUNT_FILE" > "$DISCOUNT_FILE.tmp"
    mv "$DISCOUNT_FILE.tmp" "$DISCOUNT_FILE"
    sort -n -o "$DISCOUNT_FILE" "$DISCOUNT_FILE"
    echo "Rule updated."
    echo
    read -p "Press any key to go back..." key
    edit_discounts
}

delete_discount() {
    clear
    echo "============================="
    echo "    Delete Discount Rule "
    echo "============================="
    if [ ! -s "$DISCOUNT_FILE" ]; then
        echo "No rules to delete."
        read -p "Press any key to go back..." key
        edit_discounts
        return
    fi
    awk '{printf "%s: Order >= %s tk  =>  %s%% discount\n", NR, $1, $2}' "$DISCOUNT_FILE"
    echo
    read -p "Enter rule number to delete: " rule_num
    if ! is_positive_integer "$rule_num"; then
        echo "Invalid input."
        read -p "Press any key to go back..." key
        edit_discounts
        return
    fi
    total_rules=$(wc -l < "$DISCOUNT_FILE")
    if [ "$rule_num" -gt "$total_rules" ]; then
        echo "Rule not found."
        read -p "Press any key to go back..." key
        edit_discounts
        return
    fi
    sed -i "${rule_num}d" "$DISCOUNT_FILE"
    echo "Rule deleted."
    echo
    read -p "Press any key to go back..." key
    edit_discounts
}



view_total_orders() {
    clear
    echo "============================="
    echo "   Total Number of Orders "
    echo "============================="

    total_orders=$(grep -c "^Order ID:" "$ORDERS_FILE")
    echo "Total Orders: $total_orders"

    echo "============================="
    echo
    read -p "Press any key to return to Admin Menu..." key
    admin_menu
}


customer_login() {
    customer_menu
}

customer_menu() {
    clear
    echo "============================="
    echo "        Customer Menu "
    echo "============================="
    echo
    echo "1. View Menu"
    echo "2. Place Order"
    echo "3. Pending Orders"
    echo "4. Order History"
    echo "5. View Last Order"
    echo "6. Search Item"
    echo "7. Sort Menu"
    echo "8. Exit"
    echo
    read -p "Please choose an option: " option
    case $option in
        1) view_menu_customer ;;
        2) place_order ;;
        3) customer_pending_orders ;;
        4) customer_order_history ;;
        5) view_last_order_customer ;;
        6) search_menu_item ;;
        7) sort_menu ;;
        8) welcome_screen ;;
        *) echo "Invalid option!" ; customer_menu ;;
    esac
}

view_menu_customer() {
    clear
    echo "============================="
    echo "           Menu "
    echo "============================="
    # NEW FEATURE: Basic error handling when menu is empty.
    if [ ! -s "$MENU_FILE" ]; then
        echo "Menu is empty"
    else
        cat $MENU_FILE; echo
    fi
    echo "============================="
    echo
    read -p "Press any key to return to Customer Menu..." key
    customer_menu
}

# NEW FEATURE: Search menu items by name using case-insensitive grep.
search_menu_item() {
    clear
    echo "============================="
    echo "        Search Item "
    echo "============================="
    read -p "Enter item name to search: " search_text

    # NEW FEATURE: Basic error handling when menu is empty.
    if [ ! -s "$MENU_FILE" ]; then
        echo "============================="
        echo "Menu is empty"
        echo "============================="
        echo
        read -p "Press any key to return to Customer Menu..." key
        customer_menu
        return
    fi

    echo "============================="
    if grep -i "$search_text" "$MENU_FILE"; then
        :
    else
        echo "No matching items found."
    fi
    echo "============================="
    echo
    read -p "Press any key to return to Customer Menu..." key
    customer_menu
}

# NEW FEATURE: Sort menu options for cheapest and most expensive items.
sort_menu() {
    clear
    echo "============================="
    echo "         Sort Menu "
    echo "============================="

    # NEW FEATURE: Basic error handling when menu is empty.
    if [ ! -s "$MENU_FILE" ]; then
        echo "Menu is empty"
        echo "============================="
        echo
        read -p "Press any key to return to Customer Menu..." key
        customer_menu
        return
    fi

    echo "1. Show cheapest items"
    echo "2. Show most expensive items"
    echo "3. Back"
    echo
    read -p "Please choose an option: " sort_option

    case $sort_option in
        1)
            clear
            echo "============================="
            echo "      Cheapest Items "
            echo "============================="
            sort -t '-' -k4,4n "$MENU_FILE"
            echo "============================="
            ;;
        2)
            clear
            echo "============================="
            echo "    Most Expensive Items "
            echo "============================="
            sort -t '-' -k4,4nr "$MENU_FILE"
            echo "============================="
            ;;
        3)
            customer_menu
            return
            ;;
        *)
            echo "Invalid option!"
            read -p "Press any key to continue..." key
            sort_menu
            return
            ;;
    esac

    echo
    read -p "Press any key to return to Customer Menu..." key
    customer_menu
}

place_order() {
    clear
    echo "============================="
    echo "           Menu "
    echo "============================="
    if [ ! -s "$MENU_FILE" ]; then
        echo "Menu is empty"
        echo "============================="
        echo
        read -p "Press any key to return to Customer Menu..." key
        customer_menu
        return
    fi
    cat $MENU_FILE; echo
    echo "============================="

    # Show available discounts
    if [ -s "$DISCOUNT_FILE" ]; then
        echo
        echo "--- Available Discounts ---"
        awk '{printf "  Order >= %s tk  =>  %s%% off\n", $1, $2}' "$DISCOUNT_FILE"
        echo "---------------------------"
    fi
    echo

    read -p "Enter your Name: " customer_name
    read -p "Enter your Phone Number: " phone_number

    declare -A order_items
    total_price=0
    # NEW FEATURE: Track total quantity of ordered items.
    total_quantity=0

    while true; do
        read -p "Enter Item Number to order (or 'done' to finish): " item_number
        if [[ $item_number == "done" ]]; then
            break
        fi

        # NEW FEATURE: Validate item number as positive integer.
        if ! is_positive_integer "$item_number"; then
            echo
            echo "Invalid Item Number. Please enter a number."
            continue
        fi

        if grep -q "^$item_number - " $MENU_FILE; then
            read -p "Enter quantity: " quantity

            # NEW FEATURE: Validate quantity as positive integer (> 0).
            if ! is_positive_integer "$quantity"; then
                echo
                echo "Invalid quantity. Please enter a number greater than 0."
                continue
            fi

            item_price=$(grep "^$item_number - " $MENU_FILE | awk -F ' - ' '{print $4}')
            item_name=$(grep "^$item_number - " $MENU_FILE | awk -F ' - ' '{print $2}')
            item_desc=$(grep "^$item_number - " $MENU_FILE | awk -F ' - ' '{print $3}')
            total_item_price=$((item_price * quantity))
            total_price=$((total_price + total_item_price))
            # NEW FEATURE: Keep running total of quantity.
            total_quantity=$((total_quantity + quantity))
            order_items[$item_number]="$item_name - $item_desc - $quantity - $total_item_price"
        else
            echo
            echo "Invalid Item Number. Please try again."
        fi
    done

    if [ ${#order_items[@]} -eq 0 ]; then
        echo "No items ordered."
        read -p "Press any key to return to Customer Menu..." key
        customer_menu
        return
    fi

    # Apply best matching discount
    discount_percent=0
    if [ -s "$DISCOUNT_FILE" ]; then
        while read -r threshold percent; do
            if [ "$total_price" -ge "$threshold" ]; then
                discount_percent=$percent
            fi
        done < "$DISCOUNT_FILE"
    fi

    discount_amount=0
    final_price=$total_price
    if [ "$discount_percent" -gt 0 ]; then
        discount_amount=$(( total_price * discount_percent / 100 ))
        final_price=$(( total_price - discount_amount ))
    fi

    order_id=$(date +%s)
    # Ensure orders file ends with newline before appending
    if [ -s "$ORDERS_FILE" ] && [ "$(tail -c 1 "$ORDERS_FILE" | wc -l)" -eq 0 ]; then
        echo "" >> "$ORDERS_FILE"
    fi
    echo "Order ID: $order_id" >> $ORDERS_FILE
    echo "Date: $(date)" >> $ORDERS_FILE
    echo "Status: Pending" >> $ORDERS_FILE
    echo "Customer Name: $customer_name" >> $ORDERS_FILE
    echo "Phone Number: $phone_number" >> $ORDERS_FILE
    echo "Items Ordered:" >> $ORDERS_FILE
    for item in "${!order_items[@]}"; do
        echo "$item - ${order_items[$item]}" >> $ORDERS_FILE
    done
    echo "Original Price: $total_price" >> $ORDERS_FILE
    if [ "$discount_percent" -gt 0 ]; then
        echo "Discount: $discount_percent% (-$discount_amount)" >> $ORDERS_FILE
    fi
    echo "Total Price: $final_price" >> $ORDERS_FILE
    echo "Total Items Ordered: $total_quantity" >> $ORDERS_FILE
    echo "=============================" >> $ORDERS_FILE

    echo
    echo "============================="
    echo "Order placed successfully!"
    echo "Total Items: $total_quantity"
    if [ "$discount_percent" -gt 0 ]; then
        echo "Original Price: $total_price tk"
        echo "Discount ($discount_percent%): -$discount_amount tk"
        echo "Final Price: $final_price tk"
    else
        echo "Total Price: $final_price tk"
    fi
    echo "============================="
    echo "(Order is pending. Waiting for admin to accept.)"

    echo
    read -p "Press any key to return to Customer Menu..." key
    customer_menu
}

customer_pending_orders() {
    clear
    echo "============================="
    echo "      Your Pending Orders "
    echo "============================="
    echo
    read -p "Enter your Name: " customer_name

    if [ ! -s "$ORDERS_FILE" ]; then
        echo "No orders found."
        echo "============================="
        echo
        read -p "Press any key to return to Customer Menu..." key
        customer_menu
        return
    fi

    result=$(awk -v cname="$customer_name" '
    /^Order ID:/ { block=$0"\n"; in_block=1; next }
    in_block {
        block=block $0"\n"
        if ($0 ~ /^=============================$/) {
            if (block ~ /\nStatus: Pending\n/ && index(block, "Customer Name: " cname "\n") > 0)
                printf "%s", block
            in_block=0; block=""
        }
    }' "$ORDERS_FILE")

    if [ -z "$result" ]; then
        echo "No pending orders found."
        echo "============================="
        echo
        read -p "Press any key to return to Customer Menu..." key
        customer_menu
        return
    fi

    echo "$result"
    echo "============================="
    echo
    echo "1. Cancel a Pending Order"
    echo "2. Back"
    echo
    read -p "Please choose an option: " option
    case $option in
        1) customer_cancel_order "$customer_name" ;;
        2) customer_menu ;;
        *) echo "Invalid option!" ; customer_pending_orders ;;
    esac
}

customer_cancel_order() {
    local cname="$1"
    clear
    echo "============================="
    echo "      Cancel Your Order "
    echo "============================="
    read -p "Enter Order ID to cancel: " order_id

    if ! grep -q "^Order ID: $order_id$" "$ORDERS_FILE"; then
        echo "Order ID not found."
        echo
        read -p "Press any key to go back..." key
        customer_pending_orders
        return
    fi

    # Verify it belongs to this customer and is pending
    owner=$(awk -v oid="$order_id" '
    /^Order ID:/ { if ($3 == oid) found=1 }
    found && /^Customer Name:/ { sub(/^Customer Name: /, ""); print; exit }
    ' "$ORDERS_FILE")

    status=$(awk -v oid="$order_id" '
    /^Order ID:/ { if ($3 == oid) found=1 }
    found && /^Status:/ { print $2; exit }
    ' "$ORDERS_FILE")

    if [[ "$owner" != "$cname" ]]; then
        echo "This order does not belong to you."
        echo
        read -p "Press any key to go back..." key
        customer_pending_orders
        return
    fi

    if [[ "$status" != "Pending" ]]; then
        echo "Only pending orders can be cancelled."
        echo
        read -p "Press any key to go back..." key
        customer_pending_orders
        return
    fi

    read -p "Are you sure you want to cancel Order ID $order_id? (yes/no): " confirm
    if [[ "$confirm" == "yes" ]]; then
        awk -v oid="$order_id" '
        /^Order ID:/ { if ($3 == oid) mark=1 }
        mark && /^Status: Pending/ { sub(/Pending/, "Cancelled"); mark=0 }
        { print }
        ' "$ORDERS_FILE" > "$ORDERS_FILE.tmp"
        mv "$ORDERS_FILE.tmp" "$ORDERS_FILE"
        echo "Order ID $order_id has been cancelled."
    else
        echo "Cancellation aborted."
    fi

    echo
    read -p "Press any key to return to Customer Menu..." key
    customer_menu
}

customer_order_history() {
    clear
    echo "============================="
    echo "       Order History "
    echo "============================="
    echo
    read -p "Enter your Name: " customer_name

    if [ ! -s "$ORDERS_FILE" ]; then
        echo "No orders found."
        echo "============================="
        echo
        read -p "Press any key to return to Customer Menu..." key
        customer_menu
        return
    fi

    result=$(awk -v cname="$customer_name" '
    /^Order ID:/ { block=$0"\n"; in_block=1; next }
    in_block {
        block=block $0"\n"
        if ($0 ~ /^=============================$/) {
            if (block ~ /\nStatus: Accepted\n/ && index(block, "Customer Name: " cname "\n") > 0)
                printf "%s", block
            in_block=0; block=""
        }
    }' "$ORDERS_FILE")

    if [ -z "$result" ]; then
        echo "No accepted orders found."
    else
        echo "$result"
    fi

    echo "============================="
    echo
    read -p "Press any key to return to Customer Menu..." key
    customer_menu
}

view_last_order_customer() {
    clear
    echo "============================="
    echo "      Your Last Order "
    echo "============================="
    echo

    read -p "Enter your Name: " customer_name

    if [ ! -s "$ORDERS_FILE" ]; then
        echo "No orders found."
        echo "============================="
        read -p "Press any key to return to Customer Menu..." key
        customer_menu
        return
    fi

    awk -v cname="$customer_name" '
    /^Order ID:/ { block=$0"\n"; in_block=1; next }
    in_block {
        block=block $0"\n"
        if ($0 ~ /^=============================$/) {
            if (index(block, "Customer Name: " cname "\n") > 0)
                last_block=block
            in_block=0; block=""
        }
    }
    END {
        if (last_block != "") printf "%s", last_block
        else print "No orders found for this customer."
    }' "$ORDERS_FILE"

    echo "============================="
    read -p "Press any key to return to Customer Menu..." key
    customer_menu
}

exit_screen() {
    clear
    echo "================================="
    echo " Thank you for using Restaurant Management System "
    echo "================================="
    exit 0
}

welcome_screen
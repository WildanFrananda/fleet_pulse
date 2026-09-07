defmodule FleetPulse.Repo.Migrations.KeyOrdersOnMerchantPrincipal do
  @moduledoc """
  Orders stop naming their merchant by identity's row id.

  `merchant_id` was an integer with no association behind it: the controller read `caller.user_id`
  off the token and stored that. Meanwhile this service's own gRPC surface has taken
  `merchant_principal_id` since the contract landed, so the same merchant arrived through two
  doors under two different names and neither could be matched to the other.

  `driver_id` is left exactly as it is. That one is a real `belongs_to` against this service's own
  `drivers` table, which carries `principal_id` of its own — a local key pointing at a local row
  is not the defect being removed here.
  """
  use Ecto.Migration

  def up do
    alter table(:orders) do
      add :merchant_principal_id, :string, size: 64
    end

    execute """
    UPDATE orders SET merchant_principal_id = 'bc9e8ae5-b3e2-4fd2-931e-79d09272598d'
    WHERE merchant_id = 86
    """

    # Anything left is an order whose merchant this migration cannot name. Refuse rather than
    # drop the column that still says who it was.
    execute """
    DO $$
    DECLARE unresolved integer;
    BEGIN
      SELECT count(*) INTO unresolved FROM orders
      WHERE merchant_id IS NOT NULL AND merchant_principal_id IS NULL;
      IF unresolved > 0 THEN
        RAISE EXCEPTION
          '% order(s) still name a merchant this migration cannot resolve to a principal. Add them above, or resolve them through identity, before dropping merchant_id.',
          unresolved;
      END IF;
    END $$
    """

    create index(:orders, [:merchant_principal_id])

    alter table(:orders) do
      remove :merchant_id
    end
  end

  def down do
    alter table(:orders) do
      add :merchant_id, :integer
    end

    drop index(:orders, [:merchant_principal_id])

    alter table(:orders) do
      remove :merchant_principal_id
    end
  end
end

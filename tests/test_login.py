from playwright.sync_api import sync_playwright


def test_login():
    with sync_playwright() as p:
        request = p.request.new_context()

        response = request.post(
            "http://192.168.0.196:8000/accounts/login_adminside/",
            data={
                "email": "prglakshmi@gmail.com",
                "password": "123"
            }
        )

        print("Status:", response.status)
        print("Response:", response.text())

        assert response.status == 200

        request.dispose()